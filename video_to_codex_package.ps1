param(
    [string]$InputPath,
    [string]$InputFolder = "C:\TEMP\INPUT",
    [string]$OutputFolder = "C:\DATA\TEMP",
    [string]$FFmpegPath = "C:\APPS\ffmpeg\bin\ffmpeg.exe",
    [string]$PythonExe = "py",
    [string]$WhisperModel = "base.en",
    [string]$Language = "en",
    [double]$FrameIntervalSeconds = [double]::NaN,
    [int]$HeartbeatSeconds = 10,
    [switch]$CopyRawVideo,
    [switch]$NoPrompt,
    [switch]$SkipEstimate
)

$ErrorActionPreference = "Stop"
$script:CurrentLogFile = $null

function Get-SafeFolderName {
    param([string]$Name)

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $Name

    foreach ($char in $invalid) {
        $safe = $safe.Replace($char, "_")
    }

    return $safe.Trim()
}

function Ensure-Directory {
    param([string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","PASS","FAIL")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "FAIL"  { Write-Host $line -ForegroundColor Red }
        "PASS"  { Write-Host $line -ForegroundColor Green }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line }
    }

    if ($script:CurrentLogFile) {
        Add-Content -Path $script:CurrentLogFile -Value $line -Encoding UTF8
    }
}

function Write-Phase {
    param(
        [string]$Name,
        [string]$Detail
    )

    Write-Host ""
    Write-Host ("==== {0} ====" -f $Name) -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host $Detail -ForegroundColor Cyan
    }

    $message = if ([string]::IsNullOrWhiteSpace($Detail)) {
        "PHASE: $Name"
    }
    else {
        "PHASE: $Name - $Detail"
    }

    Write-Log $message
}

function Write-PhaseResult {
    param(
        [string]$Name,
        [ValidateSet("PASS","FAIL")]
        [string]$Status,
        [string]$Detail
    )

    $message = if ([string]::IsNullOrWhiteSpace($Detail)) {
        "$Name complete"
    }
    else {
        "$Name complete - $Detail"
    }

    Write-Log $message $Status
}

function Invoke-PhaseAction {
    param(
        [string]$Name,
        [string]$Detail,
        [scriptblock]$Action
    )

    Write-Phase -Name $Name -Detail $Detail

    try {
        $result = & $Action
        Write-PhaseResult -Name $Name -Status "PASS" -Detail $Detail
        return $result
    }
    catch {
        Write-PhaseResult -Name $Name -Status "FAIL" -Detail $_.Exception.Message
        throw
    }
}

function Resolve-ExecutablePath {
    param(
        [string]$PreferredPath,
        [string[]]$FallbackCommands,
        [string[]]$FallbackPaths,
        [string]$ToolName
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        $candidates.Add($PreferredPath)
    }

    foreach ($commandName in ($FallbackCommands | Where-Object { $_ })) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            $candidates.Add($command.Source)
        }
    }

    foreach ($path in ($FallbackPaths | Where-Object { $_ })) {
        $candidates.Add($path)
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }

    throw "$ToolName not found. Checked: $($candidates -join '; ')"
}

function Get-FFprobePath {
    param([string]$FFmpegExe)

    $sibling = Join-Path (Split-Path $FFmpegExe -Parent) "ffprobe.exe"
    return Resolve-ExecutablePath `
        -PreferredPath $sibling `
        -FallbackCommands @("ffprobe") `
        -FallbackPaths @("C:\APPS\ffmpeg\bin\ffprobe.exe") `
        -ToolName "ffprobe"
}

function Quote-Argument {
    param([string]$Value)

    if ($null -eq $Value) { return '""' }
    if ($Value -eq "") { return '""' }

    if ($Value -match '[\s"]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    return $Value
}

function Invoke-ExternalCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$StepName = "External command",
        [int]$HeartbeatSeconds = 0,
        [int]$TimeoutSeconds = 1800,
        [switch]$IgnoreExitCode
    )

    $argString = (($Arguments | ForEach-Object { Quote-Argument $_ }) -join " ")
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Log "$StepName"
    Write-Log "Command: $FilePath $argString"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $argString
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $start = Get-Date
    $nextHeartbeat = if ($HeartbeatSeconds -gt 0) { $start.AddSeconds($HeartbeatSeconds) } else { $null }

    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 500

        $now = Get-Date
        $elapsed = ($now - $start).TotalSeconds

        if ($nextHeartbeat -and $now -ge $nextHeartbeat) {
            Write-Log ("{0} still working... elapsed {1:n0}s" -f $StepName, $elapsed)
            $nextHeartbeat = $now.AddSeconds($HeartbeatSeconds)
        }

        if ($TimeoutSeconds -gt 0 -and $elapsed -ge $TimeoutSeconds) {
            try { $proc.Kill() } catch { }
            throw "$StepName timed out after $TimeoutSeconds seconds."
        }
    }

    $proc.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $sw.Stop()

    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        Add-Content -Path $script:CurrentLogFile -Value "----- STDOUT: $StepName -----" -Encoding UTF8
        Add-Content -Path $script:CurrentLogFile -Value $stdout -Encoding UTF8
    }

    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        Add-Content -Path $script:CurrentLogFile -Value "----- STDERR: $StepName -----" -Encoding UTF8
        Add-Content -Path $script:CurrentLogFile -Value $stderr -Encoding UTF8
    }

    if (-not $IgnoreExitCode -and $proc.ExitCode -ne 0) {
        throw "$StepName failed with exit code $($proc.ExitCode). See log: $script:CurrentLogFile"
    }

    return [PSCustomObject]@{
        ExitCode        = $proc.ExitCode
        StdOut          = $stdout
        StdErr          = $stderr
        DurationSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 3)
    }
}

function Invoke-ExternalStreaming {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$StepName = "External command",
        [switch]$IgnoreExitCode,
        [int]$HeartbeatSeconds = 30,
        [int]$TimeoutSeconds = 1800
    )

    $argString = (($Arguments | ForEach-Object { Quote-Argument $_ }) -join " ")

    Write-Log "$StepName"
    Write-Log "Command: $FilePath $argString"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $argString
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $start = Get-Date
        $nextHeartbeat = (Get-Date).AddSeconds($HeartbeatSeconds)

        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 500

            $now = Get-Date
            $elapsed = ($now - $start).TotalSeconds
            $silence = $elapsed

            if ($now -ge $nextHeartbeat) {
                Write-Log ("{0} still working... elapsed {1:n0}s, silence {2:n0}s" -f $StepName, $elapsed, $silence)
                $nextHeartbeat = $now.AddSeconds($HeartbeatSeconds)
            }

            if ($TimeoutSeconds -gt 0 -and $elapsed -ge $TimeoutSeconds) {
                try { $proc.Kill() } catch { }
                throw "$StepName timed out after $TimeoutSeconds seconds."
            }
        }

        $proc.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $sw.Stop()
        $exitCode = $proc.ExitCode

        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            ($stdout -split "`r?`n") | ForEach-Object {
                if ($_ -ne "") {
                    Write-Host $_
                }
            }
            if ($script:CurrentLogFile) {
                Add-Content -Path $script:CurrentLogFile -Value $stdout -Encoding UTF8
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            ($stderr -split "`r?`n") | ForEach-Object {
                if ($_ -ne "") {
                    Write-Host $_ -ForegroundColor Yellow
                }
            }
            if ($script:CurrentLogFile) {
                Add-Content -Path $script:CurrentLogFile -Value $stderr -Encoding UTF8
            }
        }

        if (-not $IgnoreExitCode -and $exitCode -ne 0) {
            throw "$StepName failed with exit code $exitCode. See script_run.log."
        }

        return [PSCustomObject]@{
            ExitCode        = $exitCode
            StdOut          = $stdout
            StdErr          = $stderr
            DurationSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 3)
        }
    }
    finally {
        if ($proc) {
            $proc.Dispose()
        }
    }
}

function Test-FrameIntervalValue {
    param([double]$Value)

    if ($Value -lt 0.1 -or $Value -gt 10.0) {
        throw "Frame interval must be between 0.1 and 10.0 seconds."
    }

    $tenths = $Value * 10
    if ([math]::Abs($tenths - [math]::Round($tenths)) -gt 0.000001) {
        throw "Frame interval must be in 0.1 second increments."
    }
}

function Get-FrameIntervalLabel {
    param([double]$Value)

    return $Value.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture) -replace '\.', 'p'
}

function Get-FramesFolderName {
    param([double]$Value)

    return "frames_{0}s" -f (Get-FrameIntervalLabel -Value $Value)
}

function Get-InteractiveFrameInterval {
    param([double]$DefaultValue = 0.5)

    while ($true) {
        $raw = Read-Host ("Enter frame interval in seconds (0.1 increments, blank for {0})" -f $DefaultValue.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture))
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $DefaultValue
        }

        $parsed = 0.0
        if (-not [double]::TryParse($raw.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            Write-Host "Please enter a numeric value like 0.3, 0.5, 1.0, or 1.1." -ForegroundColor Yellow
            continue
        }

        try {
            Test-FrameIntervalValue -Value $parsed
            return $parsed
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }
}

function Format-DurationHuman {
    param([double]$Seconds)

    if ($Seconds -lt 0) { $Seconds = 0 }
    $ts = [TimeSpan]::FromSeconds([math]::Round($Seconds))
    if ($ts.TotalHours -ge 1) {
        return "{0:0}h {1:00}m {2:00}s" -f [math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds
    }
    elseif ($ts.TotalMinutes -ge 1) {
        return "{0:0}m {1:00}s" -f [math]::Floor($ts.TotalMinutes), $ts.Seconds
    }
    else {
        return "{0:0}s" -f [math]::Floor($ts.TotalSeconds)
    }
}

function Get-VideoFilesFromPath {
    param([string]$Path)

    $extensions = @(".mp4", ".mov", ".mkv", ".avi", ".m4v")

    if (-not (Test-Path $Path)) {
        throw "Path not found: $Path"
    }

    $item = Get-Item $Path

    if ($item.PSIsContainer) {
        return @(Get-ChildItem $Path -File | Where-Object { $extensions -contains $_.Extension.ToLower() })
    }

    if ($extensions -notcontains $item.Extension.ToLower()) {
        throw "Unsupported video file type: $($item.FullName)"
    }

    return @($item)
}

function Test-PythonWhisper {
    param([string]$PythonCommand)

    $result = Invoke-ExternalCapture `
        -FilePath $PythonCommand `
        -Arguments @("-c", "import whisper; print('whisper_ok')") `
        -StepName "Python Whisper import test" `
        -IgnoreExitCode

    if ($result.ExitCode -ne 0 -or $result.StdOut -notmatch 'whisper_ok') {
        throw "Python/openai-whisper not available via '$PythonCommand'. Install with: py -m pip install -U openai-whisper"
    }
}

function Test-VideoHasAudio {
    param(
        [string]$FFprobeExe,
        [string]$VideoPath
    )

    $probe = Invoke-ExternalCapture `
        -FilePath $FFprobeExe `
        -Arguments @(
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=codec_type",
            "-of", "csv=p=0",
            $VideoPath
        ) `
        -StepName "FFprobe audio stream check" `
        -IgnoreExitCode

    return ($probe.StdOut -match 'audio')
}

function Get-VideoDurationSeconds {
    param(
        [string]$FFprobeExe,
        [string]$VideoPath
    )

    $probe = Invoke-ExternalCapture `
        -FilePath $FFprobeExe `
        -Arguments @(
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            $VideoPath
        ) `
        -StepName "FFprobe duration" `
        -IgnoreExitCode

    $raw = ($probe.StdOut | Select-Object -First 1).Trim()
    $duration = 0.0
    [void][double]::TryParse($raw, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$duration)
    return $duration
}

function Test-FFmpegNvencSupport {
    param([string]$FFmpegExe)

    try {
        $output = & $FFmpegExe -hide_banner -encoders 2>&1 | Out-String
        return ($output -match 'h264_nvenc')
    }
    catch {
        return $false
    }
}

function Test-FFmpegCudaHwaccelSupport {
    param([string]$FFmpegExe)

    try {
        $output = & $FFmpegExe -hide_banner -hwaccels 2>&1 | Out-String
        return ($output -match 'cuda')
    }
    catch {
        return $false
    }
}

function Test-NvidiaSmiAvailable {
    try {
        $null = Get-Command "nvidia-smi" -ErrorAction Stop
        $output = & nvidia-smi -L 2>&1 | Out-String
        return (-not [string]::IsNullOrWhiteSpace($output) -and $output -match 'GPU')
    }
    catch {
        return $false
    }
}

function Get-WhisperExecutionMode {
    param([string]$PythonCommand)

    $tempPy = Join-Path $env:TEMP ("whisper_probe_" + [guid]::NewGuid().ToString() + ".py")

    $pyCode = @'
print("[PY-PROBE] Python process started", flush=True)
import json

result = {
    "whisper_import_ok": False,
    "torch_import_ok": False,
    "cuda_available": False,
    "device": "cpu",
    "torch_version": None,
    "cuda_version": None,
    "error": None
}

try:
    print("[PY-PROBE] Importing whisper...", flush=True)
    import whisper
    result["whisper_import_ok"] = True
except Exception as ex:
    result["error"] = f"whisper import failed: {ex}"

try:
    print("[PY-PROBE] Importing torch...", flush=True)
    import torch
    result["torch_import_ok"] = True
    result["torch_version"] = getattr(torch, "__version__", None)
    result["cuda_version"] = getattr(torch.version, "cuda", None)
    result["cuda_available"] = bool(torch.cuda.is_available())
    result["device"] = "cuda" if result["cuda_available"] else "cpu"
except Exception as ex:
    if result["error"]:
        result["error"] += f" | torch import failed: {ex}"
    else:
        result["error"] = f"torch import failed: {ex}"

print(json.dumps(result), flush=True)
'@

    Set-Content -Path $tempPy -Value $pyCode -Encoding UTF8

    try {
        $raw = Invoke-ExternalCapture `
            -FilePath $PythonCommand `
            -Arguments @($tempPy) `
            -StepName "Whisper GPU capability probe" `
            -IgnoreExitCode

        if ($raw.ExitCode -ne 0) {
            return [PSCustomObject]@{
                WhisperImportOk = $false
                TorchImportOk   = $false
                CudaAvailable   = $false
                Device          = "cpu"
                TorchVersion    = ""
                CudaVersion     = ""
                Error           = "Python probe failed. See log."
            }
        }

        $parsedJsonLine = ($raw.StdOut -split "`r?`n" | Where-Object { $_.Trim().StartsWith("{") -and $_.Trim().EndsWith("}") } | Select-Object -Last 1)
        if (-not $parsedJsonLine) {
            throw "Probe did not return valid JSON."
        }

        $parsed = $parsedJsonLine | ConvertFrom-Json

        return [PSCustomObject]@{
            WhisperImportOk = [bool]$parsed.whisper_import_ok
            TorchImportOk   = [bool]$parsed.torch_import_ok
            CudaAvailable   = [bool]$parsed.cuda_available
            Device          = [string]$parsed.device
            TorchVersion    = [string]$parsed.torch_version
            CudaVersion     = [string]$parsed.cuda_version
            Error           = [string]$parsed.error
        }
    }
    catch {
        return [PSCustomObject]@{
            WhisperImportOk = $false
            TorchImportOk   = $false
            CudaAvailable   = $false
            Device          = "cpu"
            TorchVersion    = ""
            CudaVersion     = ""
            Error           = $_.Exception.Message
        }
    }
    finally {
        if (Test-Path $tempPy) {
            Remove-Item $tempPy -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-CodexReadme {
    param(
        [string]$ReadmePath,
        [string]$VideoFileName,
        [string]$RawPresent,
        [string]$AudioPresent,
        [double]$FrameIntervalSeconds
    )

    $framesFolderName = Get-FramesFolderName -Value $FrameIntervalSeconds

@"
README_FOR_CODEX

Purpose:
This folder contains a Codex-ready review package generated from:
$VideoFileName

What is included:
- raw\                       original source video (if copied)
- proxy\review_proxy_1280.mp4
- $framesFolderName\frame_000001.jpg ...
- audio\audio.mp3            only if source audio exists
- transcript\transcript.srt  only if source audio exists
- transcript\transcript.json only if source audio exists
- frame_index.csv
- script_run.log

Recommended review order:
1. Read transcript\transcript.srt or transcript\transcript.json if present
2. Watch proxy\review_proxy_1280.mp4 for pacing and sequence
3. Use frame_index.csv to map timestamps to extracted frames
4. Inspect frames for detailed visual review
5. Use audio\audio.mp3 when spoken context needs confirmation
6. Use raw video only if derived assets are insufficient

Notes:
- Selected frame interval: $FrameIntervalSeconds seconds
- Frames folder: $framesFolderName
- Raw video present: $RawPresent
- Audio present in source: $AudioPresent
"@ | Set-Content -Path $ReadmePath -Encoding UTF8
}

function New-MasterReadme {
    param(
        [string]$MasterReadmePath,
        [string]$OutputRoot,
        [array]$ProcessedItems,
        [double]$FrameIntervalSeconds
    )

    $lines = @()
    $lines += "CODEX_MASTER_README"
    $lines += ""
    $lines += "Purpose:"
    $lines += "This root contains one Codex-ready review package per processed source video."
    $lines += ""
    $lines += "Root:"
    $lines += $OutputRoot
    $lines += ""
    $lines += "Selected frame interval:"
    $lines += "$FrameIntervalSeconds seconds"
    $lines += ""
    $lines += "Each video folder contains:"
    $lines += "- raw\                       original source video (optional)"
    $lines += "- proxy\review_proxy_1280.mp4"
    $lines += "- $(Get-FramesFolderName -Value $FrameIntervalSeconds)\frame_000001.jpg ..."
    $lines += "- audio\audio.mp3 (if source has audio)"
    $lines += "- transcript\transcript.srt (if source has audio)"
    $lines += "- transcript\transcript.json (if source has audio)"
    $lines += "- frame_index.csv"
    $lines += "- README_FOR_CODEX.txt"
    $lines += "- script_run.log"
    $lines += ""
    $lines += "Processed video folders:"
    foreach ($item in $ProcessedItems) {
        $lines += "- $($item.OutputFolderName)  <=  $($item.SourceVideoName)"
    }

    $lines | Set-Content -Path $MasterReadmePath -Encoding UTF8
}

function Add-SummaryRow {
    param(
        [string]$SummaryCsv,
        [string]$SourceVideo,
        [string]$OutputFolderName,
        [string]$OutputPath,
        [int]$FrameCount,
        [string]$ProxyVideo,
        [string]$AudioFile,
        [string]$TranscriptSrt,
        [string]$TranscriptJson,
        [string]$RawCopied,
        [string]$AudioPresent,
        [string]$ProxyMode,
        [string]$FrameMode,
        [string]$WhisperMode,
        [double]$FrameIntervalSeconds
    )

    $row = [PSCustomObject]@{
        source_video           = $SourceVideo
        output_folder_name     = $OutputFolderName
        output_path            = $OutputPath
        frame_count            = $FrameCount
        frame_interval_seconds = $FrameIntervalSeconds
        frames_folder          = (Get-FramesFolderName -Value $FrameIntervalSeconds)
        proxy_video            = $ProxyVideo
        audio_file             = $AudioFile
        transcript_srt         = $TranscriptSrt
        transcript_json        = $TranscriptJson
        raw_copied             = $RawCopied
        audio_present          = $AudioPresent
        proxy_mode             = $ProxyMode
        frame_mode             = $FrameMode
        whisper_mode           = $WhisperMode
    }

    if (-not (Test-Path $SummaryCsv)) {
        $row | Export-Csv -Path $SummaryCsv -NoTypeInformation -Encoding UTF8
    }
    else {
        $row | Export-Csv -Path $SummaryCsv -NoTypeInformation -Encoding UTF8 -Append
    }
}

function Invoke-PythonWhisperTranscript {
    param(
        [string]$PythonCommand,
        [string]$AudioPath,
        [string]$TranscriptFolder,
        [string]$ModelName,
        [string]$LanguageCode,
        [string]$FFmpegExe,
        [bool]$PreferGpu,
        [int]$HeartbeatSeconds = 10
    )

    Ensure-Directory $TranscriptFolder

    $ffmpegDir = Split-Path $FFmpegExe -Parent
    $tempPy = Join-Path $env:TEMP ("whisper_transcribe_" + [guid]::NewGuid().ToString() + ".py")

    $pyCode = @'
print("[PY] Python process started", flush=True)

import json
import os
import sys
import traceback
import time
import threading

audio_path = sys.argv[1]
output_dir = sys.argv[2]
model_name = sys.argv[3]
language_code = sys.argv[4]
ffmpeg_dir = sys.argv[5]
prefer_gpu = sys.argv[6].lower() == "true"

os.makedirs(output_dir, exist_ok=True)

if ffmpeg_dir:
    os.environ["PATH"] = ffmpeg_dir + os.pathsep + os.environ.get("PATH", "")

def log(msg):
    print(msg, flush=True)

heartbeat_stop = False

def heartbeat():
    started = time.time()
    while not heartbeat_stop:
        elapsed = time.time() - started
        log(f"[PY] heartbeat: transcription process alive, elapsed={elapsed:.0f}s")
        time.sleep(30)

hb = threading.Thread(target=heartbeat, daemon=True)
hb.start()

try:
    import whisper
except Exception:
    traceback.print_exc(file=sys.stderr)
    sys.exit(10)

torch = None
if prefer_gpu:
    try:
        import torch
    except Exception as ex:
        log(f"[PY] Torch import failed. GPU path disabled. {ex}")
        torch = None

def fmt_srt_time(seconds):
    total_ms = int(round(float(seconds) * 1000))
    hours = total_ms // 3600000
    total_ms %= 3600000
    minutes = total_ms // 60000
    total_ms %= 60000
    seconds_part = total_ms // 1000
    millis = total_ms % 1000
    return f"{hours:02}:{minutes:02}:{seconds_part:02},{millis:03}"

def run_transcription(device_name):
    fp16 = device_name == "cuda"
    log(f"[PY] Loading model '{model_name}' on device '{device_name}'...")
    model = whisper.load_model(model_name, device=device_name)
    log(f"[PY] Starting transcription on {device_name}...")
    result = model.transcribe(
        audio_path,
        language=language_code if language_code else None,
        verbose=True,
        fp16=fp16
    )
    return result, fp16

device = "cpu"
fp16 = False
gpu_error = ""
result = None

try:
    log(f"[PY] Audio input: {audio_path}")
    log(f"[PY] Output dir: {output_dir}")

    if prefer_gpu and torch is not None and torch.cuda.is_available():
        try:
            device = "cuda"
            result, fp16 = run_transcription("cuda")
        except Exception as ex:
            gpu_error = str(ex)
            log(f"[PY] GPU transcription failed. Retrying on CPU. {ex}")
            traceback.print_exc(file=sys.stderr)
            device = "cpu"

    if result is None:
        result, fp16 = run_transcription("cpu")
        device = "cpu"

    log("[PY] Writing transcript files...")

    srt_path = os.path.join(output_dir, "transcript.srt")
    json_path = os.path.join(output_dir, "transcript.json")

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    with open(srt_path, "w", encoding="utf-8") as f:
        segments = result.get("segments") or []
        for index, seg in enumerate(segments, start=1):
            start_ts = fmt_srt_time(seg.get("start", 0))
            end_ts = fmt_srt_time(seg.get("end", 0))
            text = (seg.get("text") or "").strip()
            f.write(f"{index}\n{start_ts} --> {end_ts}\n{text}\n\n")

    log("[PY] Transcript files written successfully.")

    print(json.dumps({
        "device": device,
        "fp16": fp16,
        "json_path": json_path,
        "srt_path": srt_path,
        "gpu_error": gpu_error
    }), flush=True)

except Exception:
    traceback.print_exc(file=sys.stderr)
    sys.exit(20)

finally:
    heartbeat_stop = True
'@

    Set-Content -Path $tempPy -Value $pyCode -Encoding UTF8

    try {
        $result = Invoke-ExternalStreaming `
            -FilePath $PythonCommand `
            -Arguments @(
                $tempPy,
                $AudioPath,
                $TranscriptFolder,
                $ModelName,
                $LanguageCode,
                $ffmpegDir,
                $PreferGpu.ToString()
            ) `
            -StepName "Python Whisper transcription" `
            -IgnoreExitCode `
            -HeartbeatSeconds $HeartbeatSeconds `
            -TimeoutSeconds 1800

        if ($result.ExitCode -ne 0) {
            throw "Python Whisper transcription failed. See script_run.log for the exact Python error."
        }

        $parsedJsonLine = ($result.StdOut -split "`r?`n" | Where-Object { $_.Trim().StartsWith("{") -and $_.Trim().EndsWith("}") } | Select-Object -Last 1)

        if (-not $parsedJsonLine) {
            throw "Python Whisper transcription did not return a parsable result. See script_run.log."
        }

        $parsed = $parsedJsonLine | ConvertFrom-Json

        return [PSCustomObject]@{
            Device   = [string]$parsed.device
            Fp16     = [bool]$parsed.fp16
            JsonPath = [string]$parsed.json_path
            SrtPath  = [string]$parsed.srt_path
            GpuError = [string]$parsed.gpu_error
        }
    }
    finally {
        if (Test-Path $tempPy) {
            Remove-Item $tempPy -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-FpsFilterForInterval {
    param([double]$FrameIntervalSeconds)

    Test-FrameIntervalValue -Value $FrameIntervalSeconds
    $fps = 1.0 / $FrameIntervalSeconds
    return ("fps={0}" -f $fps.ToString("0.########", [System.Globalization.CultureInfo]::InvariantCulture))
}

function New-ProxyVideo {
    param(
        [string]$FFmpegExe,
        [string]$InputVideo,
        [string]$OutputVideo,
        [bool]$HasAudio,
        [bool]$UseGpu,
        [int]$HeartbeatSeconds = 10
    )

    if (Test-Path $OutputVideo) {
        Write-Log "Proxy video already exists. Skipping."
        return "SKIPPED_EXISTING"
    }

    $gpuArgs = @("-y", "-hwaccel", "cuda", "-i", $InputVideo, "-map", "0:v:0")
    $cpuArgs = @("-y", "-i", $InputVideo, "-map", "0:v:0")

    if ($HasAudio) {
        $gpuArgs += @("-map", "0:a:0", "-vf", "scale=1280:-2", "-c:v", "h264_nvenc", "-preset", "p5", "-cq", "23", "-c:a", "aac", "-b:a", "192k", $OutputVideo)
        $cpuArgs += @("-map", "0:a:0", "-vf", "scale=1280:-2", "-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac", "-b:a", "192k", $OutputVideo)
    }
    else {
        $gpuArgs += @("-vf", "scale=1280:-2", "-c:v", "h264_nvenc", "-preset", "p5", "-cq", "23", "-an", $OutputVideo)
        $cpuArgs += @("-vf", "scale=1280:-2", "-c:v", "libx264", "-preset", "medium", "-crf", "23", "-an", $OutputVideo)
    }

    if ($UseGpu) {
        Write-Log "Creating proxy video with NVIDIA NVENC..."

        $gpuResult = Invoke-ExternalCapture -FilePath $FFmpegExe -Arguments $gpuArgs -StepName "Proxy generation (GPU)" -HeartbeatSeconds $HeartbeatSeconds -IgnoreExitCode
        if ($gpuResult.ExitCode -eq 0 -and (Test-Path $OutputVideo)) {
            return "GPU_NVENC"
        }

        Write-Log "GPU proxy generation failed. Falling back to CPU libx264." "WARN"
        if (Test-Path $OutputVideo) {
            Remove-Item -Path $OutputVideo -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Log "Creating proxy video with CPU libx264..."
    $cpuResult = Invoke-ExternalCapture -FilePath $FFmpegExe -Arguments $cpuArgs -StepName "Proxy generation (CPU)" -HeartbeatSeconds $HeartbeatSeconds
    if ($cpuResult.ExitCode -ne 0 -or -not (Test-Path $OutputVideo)) {
        throw "Proxy video generation failed."
    }

    return "CPU_LIBX264"
}

function Extract-FramesAtInterval {
    param(
        [string]$FFmpegExe,
        [string]$InputVideo,
        [string]$FramesFolder,
        [bool]$UseGpu,
        [double]$FrameIntervalSeconds,
        [int]$HeartbeatSeconds = 10
    )

    $existingFrames = @(Get-ChildItem $FramesFolder -Filter "frame_*.jpg" -ErrorAction SilentlyContinue)
    if ($existingFrames.Count -gt 0) {
        Write-Log "Frames already exist. Skipping frame extraction."
        return "SKIPPED_EXISTING"
    }

    $outputPattern = Join-Path $FramesFolder "frame_%06d.jpg"
    $fpsFilter = Get-FpsFilterForInterval -FrameIntervalSeconds $FrameIntervalSeconds
    $vf = "$fpsFilter,scale=1280:-2"

    $gpuArgs = @("-y", "-hwaccel", "cuda", "-i", $InputVideo, "-map", "0:v:0", "-vf", $vf, "-q:v", "3", $outputPattern)
    $cpuArgs = @("-y", "-i", $InputVideo, "-map", "0:v:0", "-vf", $vf, "-q:v", "3", $outputPattern)

    if ($UseGpu) {
        Write-Log "Extracting frames every $FrameIntervalSeconds seconds with CUDA decode attempt..."

        $gpuResult = Invoke-ExternalCapture -FilePath $FFmpegExe -Arguments $gpuArgs -StepName "Frame extraction (GPU)" -HeartbeatSeconds $HeartbeatSeconds -IgnoreExitCode
        if ($gpuResult.ExitCode -eq 0 -and @(Get-ChildItem $FramesFolder -Filter "frame_*.jpg" -ErrorAction SilentlyContinue).Count -gt 0) {
            return "GPU_DECODE_ATTEMPT"
        }

        Write-Log "GPU-assisted frame extraction failed. Falling back to CPU." "WARN"
        Get-ChildItem $FramesFolder -Filter "frame_*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Extracting frames every $FrameIntervalSeconds seconds with CPU path..."
    $cpuResult = Invoke-ExternalCapture -FilePath $FFmpegExe -Arguments $cpuArgs -StepName "Frame extraction (CPU)" -HeartbeatSeconds $HeartbeatSeconds
    if ($cpuResult.ExitCode -ne 0 -or @(Get-ChildItem $FramesFolder -Filter "frame_*.jpg" -ErrorAction SilentlyContinue).Count -eq 0) {
        throw "Frame extraction failed."
    }

    return "CPU"
}

function Export-AudioMp3 {
    param(
        [string]$FFmpegExe,
        [string]$InputVideo,
        [string]$AudioFile,
        [int]$HeartbeatSeconds = 10
    )

    if (Test-Path $AudioFile) {
        Write-Log "Audio file already exists. Skipping extraction."
        return "SKIPPED_EXISTING"
    }

    $result = Invoke-ExternalCapture `
        -FilePath $FFmpegExe `
        -Arguments @("-y", "-i", $InputVideo, "-map", "0:a:0", "-vn", "-c:a", "libmp3lame", "-b:a", "192k", $AudioFile) `
        -StepName "Audio extraction" `
        -HeartbeatSeconds $HeartbeatSeconds

    if ($result.ExitCode -ne 0 -or -not (Test-Path $AudioFile)) {
        throw "Audio extraction failed."
    }

    return "CREATED"
}

function Get-BenchmarkProxySeconds {
    param(
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [string]$VideoPath,
        [bool]$HasAudio,
        [bool]$UseGpu
    )

    $tempOut = Join-Path $env:TEMP ("proxy_bench_" + [guid]::NewGuid().ToString() + ".mp4")
    $sampleSeconds = Get-BenchmarkSampleDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $VideoPath -MaximumSampleSeconds 20.0

    try {
        if ($sampleSeconds -le 0) {
            return $null
        }

        $sampleText = $sampleSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)

        if ($UseGpu) {
            $gpuArgs = @("-y", "-hwaccel", "cuda", "-ss", "0", "-t", $sampleText, "-i", $VideoPath, "-map", "0:v:0")
            if ($HasAudio) {
                $gpuArgs += @("-map", "0:a:0", "-vf", "scale=1280:-2", "-c:v", "h264_nvenc", "-preset", "p5", "-cq", "23", "-c:a", "aac", "-b:a", "192k", $tempOut)
            }
            else {
                $gpuArgs += @("-vf", "scale=1280:-2", "-c:v", "h264_nvenc", "-preset", "p5", "-cq", "23", "-an", $tempOut)
            }

            $gpuResult = Invoke-ExternalCapture -FilePath $FFmpegExe -Arguments $gpuArgs -StepName "Benchmark proxy generation (GPU)" -IgnoreExitCode
            if ($gpuResult.ExitCode -eq 0) {
                return [PSCustomObject]@{Elapsed=$gpuResult.DurationSeconds; Sample=$sampleSeconds}
            }
        }

        $cpuArgs = @("-y", "-ss", "0", "-t", $sampleText, "-i", $VideoPath, "-map", "0:v:0")
        if ($HasAudio) {
            $cpuArgs += @("-map", "0:a:0", "-vf", "scale=1280:-2", "-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac", "-b:a", "192k", $tempOut)
        }
        else {
            $cpuArgs += @("-vf", "scale=1280:-2", "-c:v", "libx264", "-preset", "medium", "-crf", "23", "-an", $tempOut)
        }

        $cpuResult = Invoke-ExternalCapture -FilePath $FFmpegExe -Arguments $cpuArgs -StepName "Benchmark proxy generation (CPU)"
        return [PSCustomObject]@{Elapsed=$cpuResult.DurationSeconds; Sample=$sampleSeconds}
    }
    finally {
        if (Test-Path $tempOut) { Remove-Item $tempOut -Force -ErrorAction SilentlyContinue }
    }
}

function Get-BenchmarkFramesSeconds {
    param(
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [string]$VideoPath,
        [bool]$UseGpu,
        [double]$FrameIntervalSeconds
    )

    $tempDir = Join-Path $env:TEMP ("frames_bench_" + [guid]::NewGuid().ToString())
    Ensure-Directory $tempDir
    $sampleSeconds = Get-BenchmarkSampleDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $VideoPath -MaximumSampleSeconds 30.0
    $fpsFilter = Get-FpsFilterForInterval -FrameIntervalSeconds $FrameIntervalSeconds
    $vf = "$fpsFilter,scale=1280:-2"
    $outputPattern = Join-Path $tempDir "frame_%06d.jpg"

    try {
        if ($sampleSeconds -le 0) {
            return $null
        }

        $sampleText = $sampleSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        if ($UseGpu) {
            $gpuResult = Invoke-ExternalCapture `
                -FilePath $FFmpegExe `
                -Arguments @("-y", "-hwaccel", "cuda", "-ss", "0", "-t", $sampleText, "-i", $VideoPath, "-map", "0:v:0", "-vf", $vf, "-q:v", "3", $outputPattern) `
                -StepName "Benchmark frame extraction (GPU)" `
                -IgnoreExitCode

            if ($gpuResult.ExitCode -eq 0 -and @(Get-ChildItem $tempDir -Filter "frame_*.jpg" -ErrorAction SilentlyContinue).Count -gt 0) {
                return [PSCustomObject]@{Elapsed=$gpuResult.DurationSeconds; Sample=$sampleSeconds}
            }

            Get-ChildItem $tempDir -Filter "frame_*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        $cpuResult = Invoke-ExternalCapture `
            -FilePath $FFmpegExe `
            -Arguments @("-y", "-ss", "0", "-t", $sampleText, "-i", $VideoPath, "-map", "0:v:0", "-vf", $vf, "-q:v", "3", $outputPattern) `
            -StepName "Benchmark frame extraction (CPU)"

        return [PSCustomObject]@{Elapsed=$cpuResult.DurationSeconds; Sample=$sampleSeconds}
    }
    finally {
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Get-BenchmarkAudioSeconds {
    param(
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [string]$VideoPath
    )

    $tempOut = Join-Path $env:TEMP ("audio_bench_" + [guid]::NewGuid().ToString() + ".mp3")
    $sampleSeconds = Get-BenchmarkSampleDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $VideoPath -MaximumSampleSeconds 45.0

    try {
        if ($sampleSeconds -le 0) {
            return $null
        }

        $sampleText = $sampleSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $result = Invoke-ExternalCapture `
            -FilePath $FFmpegExe `
            -Arguments @("-y", "-ss", "0", "-t", $sampleText, "-i", $VideoPath, "-map", "0:a:0", "-vn", "-c:a", "libmp3lame", "-b:a", "192k", $tempOut) `
            -StepName "Benchmark audio extraction"

        return [PSCustomObject]@{Elapsed=$result.DurationSeconds; Sample=$sampleSeconds}
    }
    finally {
        if (Test-Path $tempOut) { Remove-Item $tempOut -Force -ErrorAction SilentlyContinue }
    }
}

function Get-BenchmarkSampleDurationSeconds {
    param(
        [string]$FFprobeExe,
        [string]$VideoPath,
        [double]$MaximumSampleSeconds
    )

    $duration = Get-VideoDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $VideoPath
    if ($duration -le 0) {
        return 0.0
    }

    return [math]::Min($duration, $MaximumSampleSeconds)
}

function Get-BestEffortEstimate {
    param(
        [array]$Videos,
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [string]$PythonCommand,
        [string]$ModelName,
        [string]$LanguageCode,
        [bool]$CanUseFfmpegGpu,
        [bool]$CanUseWhisperGpu,
        [double]$FrameIntervalSeconds
    )

    try {
        $totalDuration = 0.0
        foreach ($video in $Videos) {
            $totalDuration += Get-VideoDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $video.FullName
        }

        if ($Videos.Count -eq 0 -or $totalDuration -le 0) {
            return $null
        }

        $sampleVideo = $Videos[0]
        $hasAudio = Test-VideoHasAudio -FFprobeExe $FFprobeExe -VideoPath $sampleVideo.FullName
        $warnings = New-Object System.Collections.Generic.List[string]

        Write-Phase -Name "Estimate" -Detail "Running best-effort runtime estimate. Failures here will not stop processing."

        $proxyBench = $null
        $framesBench = $null
        $audioBench = $null

        try {
            $proxyBench = Get-BenchmarkProxySeconds -FFmpegExe $FFmpegExe -FFprobeExe $FFprobeExe -VideoPath $sampleVideo.FullName -HasAudio $hasAudio -UseGpu $CanUseFfmpegGpu
        }
        catch {
            $warnings.Add("Proxy estimate unavailable: $($_.Exception.Message)")
        }

        try {
            $framesBench = Get-BenchmarkFramesSeconds -FFmpegExe $FFmpegExe -FFprobeExe $FFprobeExe -VideoPath $sampleVideo.FullName -UseGpu $CanUseFfmpegGpu -FrameIntervalSeconds $FrameIntervalSeconds
        }
        catch {
            $warnings.Add("Frame estimate unavailable: $($_.Exception.Message)")
        }

        if ($hasAudio) {
            try {
                $audioBench = Get-BenchmarkAudioSeconds -FFmpegExe $FFmpegExe -FFprobeExe $FFprobeExe -VideoPath $sampleVideo.FullName
            }
            catch {
                $warnings.Add("Audio estimate unavailable: $($_.Exception.Message)")
            }
        }

        $proxyEstimate = 0.0
        $framesEstimate = 0.0
        $audioEstimate = 0.0
        $whisperEstimate = 0.0

        if ($proxyBench) {
            $proxyEstimate = ($proxyBench.Elapsed / $proxyBench.Sample) * $totalDuration
        }

        if ($framesBench) {
            $frameLoadFactor = 0.5 / $FrameIntervalSeconds
            $framesEstimate = (($framesBench.Elapsed / $framesBench.Sample) * $totalDuration) * $frameLoadFactor
        }

        if ($audioBench) {
            $audioEstimate = ($audioBench.Elapsed / $audioBench.Sample) * $totalDuration
        }

        if ($hasAudio) {
            $whisperFactor = if ($CanUseWhisperGpu) { 0.45 } else { 1.25 }
            $whisperEstimate = $totalDuration * $whisperFactor
            $warnings.Add(("Whisper estimate uses a {0} heuristic rather than a transcription benchmark so estimation can never kill the real run." -f $(if ($CanUseWhisperGpu) { "GPU" } else { "CPU" })))
        }

        $indexEstimate = (($totalDuration / [math]::Max($FrameIntervalSeconds, 0.1)) * 0.0025)
        $totalEstimate = $proxyEstimate + $framesEstimate + $audioEstimate + $whisperEstimate + $indexEstimate

        return [PSCustomObject]@{
            TotalDurationSeconds   = $totalDuration
            ProxyEstimateSeconds   = $proxyEstimate
            FramesEstimateSeconds  = $framesEstimate
            AudioEstimateSeconds   = $audioEstimate
            WhisperEstimateSeconds = $whisperEstimate
            IndexEstimateSeconds   = $indexEstimate
            TotalEstimateSeconds   = $totalEstimate
            Warnings               = @($warnings)
        }
    }
    catch {
        Write-Log "Runtime estimation failed. Continuing with processing. $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Build-FrameIndex {
    param(
        [string]$FramesFolder,
        [string]$FrameIndexCsv,
        [double]$FrameIntervalSeconds,
        [string]$FramesFolderName,
        [int]$HeartbeatSeconds = 10
    )

    Write-Log "Building frame index..."
    "frame_number,seconds,timestamp,filename,relative_path" | Set-Content -Path $FrameIndexCsv -Encoding UTF8

    $frames = @(Get-ChildItem $FramesFolder -Filter "frame_*.jpg" | Sort-Object Name)
    $nextHeartbeat = if ($HeartbeatSeconds -gt 0) { (Get-Date).AddSeconds($HeartbeatSeconds) } else { $null }

    for ($i = 0; $i -lt $frames.Count; $i++) {
        $frame = $frames[$i]
        if ($frame.BaseName -match '^frame_(\d+)$') {
            $frameNumber = [int]$matches[1]
            $seconds = [math]::Round(($frameNumber - 1) * $FrameIntervalSeconds, 3)
            $timestamp = [TimeSpan]::FromSeconds($seconds).ToString("hh\:mm\:ss\.fff")
            $relativePath = "$FramesFolderName/$($frame.Name)"
            "$frameNumber,$seconds,$timestamp,$($frame.Name),$relativePath" | Add-Content -Path $FrameIndexCsv -Encoding UTF8
        }

        $processed = $i + 1
        $now = Get-Date
        if (($nextHeartbeat -and $now -ge $nextHeartbeat) -or ($processed % 250 -eq 0 -and $processed -lt $frames.Count)) {
            Write-Log ("Frame indexing still working... {0}/{1} frames indexed" -f $processed, $frames.Count)
            if ($HeartbeatSeconds -gt 0) {
                $nextHeartbeat = $now.AddSeconds($HeartbeatSeconds)
            }
        }
    }

    return $frames.Count
}

function Process-Video {
    param(
        [string]$VideoPath,
        [string]$BaseOutputFolder,
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [string]$PythonCommand,
        [string]$ModelName,
        [string]$LanguageCode,
        [bool]$DoCopyRaw,
        [string]$SummaryCsv,
        [bool]$CanUseFfmpegGpu,
        [bool]$CanUseWhisperGpu,
        [double]$FrameIntervalSeconds,
        [int]$HeartbeatSeconds = 10
    )

    if (-not (Test-Path $VideoPath)) {
        throw "Input video not found: $VideoPath"
    }

    $videoItem = Get-Item $VideoPath
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($videoItem.Name)
    $safeBaseName = Get-SafeFolderName $baseName

    $framesFolderName = Get-FramesFolderName -Value $FrameIntervalSeconds
    $videoOutputRoot = Join-Path $BaseOutputFolder $safeBaseName
    $rawFolder = Join-Path $videoOutputRoot "raw"
    $proxyFolder = Join-Path $videoOutputRoot "proxy"
    $framesFolder = Join-Path $videoOutputRoot $framesFolderName
    $audioFolder = Join-Path $videoOutputRoot "audio"
    $transcriptFolder = Join-Path $videoOutputRoot "transcript"

    $proxyVideo = Join-Path $proxyFolder "review_proxy_1280.mp4"
    $audioFile = Join-Path $audioFolder "audio.mp3"
    $transcriptSrt = Join-Path $transcriptFolder "transcript.srt"
    $transcriptJson = Join-Path $transcriptFolder "transcript.json"
    $frameIndexCsv = Join-Path $videoOutputRoot "frame_index.csv"
    $readmeFile = Join-Path $videoOutputRoot "README_FOR_CODEX.txt"
    $rawVideoPath = Join-Path $rawFolder $videoItem.Name
    $logFile = Join-Path $videoOutputRoot "script_run.log"

    Ensure-Directory $videoOutputRoot
    Ensure-Directory $rawFolder
    Ensure-Directory $proxyFolder
    Ensure-Directory $framesFolder
    Ensure-Directory $audioFolder
    Ensure-Directory $transcriptFolder

    $script:CurrentLogFile = $logFile
    "==== Script run started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====" | Set-Content -Path $logFile -Encoding UTF8

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ("Processing: {0}" -f $videoItem.FullName) -ForegroundColor Cyan
    Write-Host ("Output:     {0}" -f $videoOutputRoot) -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Log "Processing video: $($videoItem.FullName)"
    Write-Log "Output folder: $videoOutputRoot"
    Write-Log "Selected frame interval: $FrameIntervalSeconds seconds"

    $preflightResult = Invoke-PhaseAction -Name "Preflight" -Detail $videoItem.Name -Action {
        $phaseHasAudio = Test-VideoHasAudio -FFprobeExe $FFprobeExe -VideoPath $videoItem.FullName
        $phaseAudioPresentText = if ($phaseHasAudio) { "Yes" } else { "No" }
        Write-Log "Source audio present: $phaseAudioPresentText"

        return [PSCustomObject]@{
            HasAudio         = $phaseHasAudio
            AudioPresentText = $phaseAudioPresentText
        }
    }
    $hasAudio = [bool]$preflightResult.HasAudio
    $audioPresentText = [string]$preflightResult.AudioPresentText

    if ($DoCopyRaw) {
        Invoke-PhaseAction -Name "Raw" -Detail $videoItem.Name -Action {
            if (-not (Test-Path $rawVideoPath)) {
                Write-Log "Copying raw video..."
                Copy-Item -Path $videoItem.FullName -Destination $rawVideoPath -Force
            }
            else {
                Write-Log "Raw video already copied. Skipping."
            }
        } | Out-Null
    }

    $proxyMode = Invoke-PhaseAction -Name "Proxy" -Detail $videoItem.Name -Action {
        New-ProxyVideo `
            -FFmpegExe $FFmpegExe `
            -InputVideo $videoItem.FullName `
            -OutputVideo $proxyVideo `
            -HasAudio $hasAudio `
            -UseGpu $CanUseFfmpegGpu `
            -HeartbeatSeconds $HeartbeatSeconds
    }

    $frameMode = Invoke-PhaseAction -Name "Frames" -Detail ("{0} at {1:0.0}s" -f $videoItem.Name, $FrameIntervalSeconds) -Action {
        Extract-FramesAtInterval `
            -FFmpegExe $FFmpegExe `
            -InputVideo $videoItem.FullName `
            -FramesFolder $framesFolder `
            -UseGpu $CanUseFfmpegGpu `
            -FrameIntervalSeconds $FrameIntervalSeconds `
            -HeartbeatSeconds $HeartbeatSeconds
    }

    $whisperMode = "SKIPPED_NO_AUDIO"

    if ($hasAudio) {
        Invoke-PhaseAction -Name "Audio" -Detail $videoItem.Name -Action {
            $null = Export-AudioMp3 -FFmpegExe $FFmpegExe -InputVideo $videoItem.FullName -AudioFile $audioFile -HeartbeatSeconds $HeartbeatSeconds
        } | Out-Null

        $whisperMode = Invoke-PhaseAction -Name "Transcript" -Detail $videoItem.Name -Action {
            if ((Test-Path $transcriptSrt) -and (Test-Path $transcriptJson)) {
                Write-Log "Transcript files already exist. Skipping Whisper transcription."
                return "SKIPPED_EXISTING"
            }
            else {
                $phaseWhisperMode = "CPU"
                if ($CanUseWhisperGpu) {
                    Write-Log "Generating transcript with Whisper on GPU if available..."
                    $phaseWhisperMode = "GPU_CUDA"
                }
                else {
                    Write-Log "Generating transcript with Whisper on CPU..."
                }

                $transcriptResult = Invoke-PythonWhisperTranscript `
                    -PythonCommand $PythonCommand `
                    -AudioPath $audioFile `
                    -TranscriptFolder $transcriptFolder `
                    -ModelName $ModelName `
                    -LanguageCode $LanguageCode `
                    -FFmpegExe $FFmpegExe `
                    -PreferGpu $CanUseWhisperGpu `
                    -HeartbeatSeconds $HeartbeatSeconds

                if (-not (Test-Path $transcriptSrt)) {
                    throw "Expected SRT not found: $transcriptSrt"
                }

                if (-not (Test-Path $transcriptJson)) {
                    throw "Expected JSON not found: $transcriptJson"
                }

                if ($transcriptResult.Device -eq "cuda") {
                    $phaseWhisperMode = "GPU_CUDA"
                }
                else {
                    $phaseWhisperMode = "CPU"
                }

                if ($transcriptResult.GpuError) {
                    Write-Log "Whisper GPU fallback note: $($transcriptResult.GpuError)" "WARN"
                }

                Write-Log "Whisper transcript completed using device: $($transcriptResult.Device)"
                return $phaseWhisperMode
            }
        }
    }
    else {
        Write-Log "Skipping audio extraction: source file has no audio stream."
        Write-Log "Skipping transcript generation: source file has no audio stream."
        $audioFile = ""
        $transcriptSrt = ""
        $transcriptJson = ""
        Write-PhaseResult -Name "Audio" -Status "PASS" -Detail "Skipped because source has no audio"
        Write-PhaseResult -Name "Transcript" -Status "PASS" -Detail "Skipped because source has no audio"
    }

    $frameCount = Invoke-PhaseAction -Name "Index" -Detail $videoItem.Name -Action {
        Build-FrameIndex `
            -FramesFolder $framesFolder `
            -FrameIndexCsv $frameIndexCsv `
            -FrameIntervalSeconds $FrameIntervalSeconds `
            -FramesFolderName $framesFolderName `
            -HeartbeatSeconds $HeartbeatSeconds
    }

    if ($frameCount -le 0) {
        throw "No frames were extracted to $framesFolder"
    }
    $rawPresent = if ($DoCopyRaw) { "Yes" } else { "No" }

    Invoke-PhaseAction -Name "README" -Detail $videoItem.Name -Action {
        New-CodexReadme `
            -ReadmePath $readmeFile `
            -VideoFileName $videoItem.Name `
            -RawPresent $rawPresent `
            -AudioPresent $audioPresentText `
            -FrameIntervalSeconds $FrameIntervalSeconds
    } | Out-Null

    Add-SummaryRow `
        -SummaryCsv $SummaryCsv `
        -SourceVideo $videoItem.Name `
        -OutputFolderName $safeBaseName `
        -OutputPath $videoOutputRoot `
        -FrameCount $frameCount `
        -ProxyVideo $proxyVideo `
        -AudioFile $audioFile `
        -TranscriptSrt $transcriptSrt `
        -TranscriptJson $transcriptJson `
        -RawCopied $rawPresent `
        -AudioPresent $audioPresentText `
        -ProxyMode $proxyMode `
        -FrameMode $frameMode `
        -WhisperMode $whisperMode `
        -FrameIntervalSeconds $FrameIntervalSeconds

    return [PSCustomObject]@{
        SourceVideoName  = $videoItem.Name
        OutputFolderName = $safeBaseName
        OutputPath       = $videoOutputRoot
        FrameCount       = $frameCount
        AudioPresent     = $audioPresentText
        ProxyMode        = $proxyMode
        FrameMode        = $frameMode
        WhisperMode      = $whisperMode
        FramesFolderName = $framesFolderName
    }
}

Write-Phase -Name "Preflight" -Detail "Resolving tools and inputs"

$FFmpegPath = Resolve-ExecutablePath `
    -PreferredPath $FFmpegPath `
    -FallbackCommands @("ffmpeg") `
    -FallbackPaths @("C:\APPS\ffmpeg\bin\ffmpeg.exe", "C:\Program Files\digiKam\ffmpeg.exe") `
    -ToolName "FFmpeg"
$FFprobePath = Get-FFprobePath -FFmpegExe $FFmpegPath
$PythonExe = Resolve-ExecutablePath `
    -PreferredPath $PythonExe `
    -FallbackCommands @("py", "python") `
    -FallbackPaths @() `
    -ToolName "Python launcher"

Ensure-Directory $InputFolder
Ensure-Directory $OutputFolder

$requestedInputPath = $InputPath
if (-not $PSBoundParameters.ContainsKey("InputPath") -and -not $NoPrompt) {
    Write-Host ""
    Write-Host "Default input source:"
    Write-Host $InputFolder
    $customInput = Read-Host "Press Enter to use that folder, or type a different full video file or folder path"
    if (-not [string]::IsNullOrWhiteSpace($customInput)) {
        $requestedInputPath = $customInput.Trim()
    }
}

$InputPath = $requestedInputPath

$requestedOutputFolder = $OutputFolder
if (-not $PSBoundParameters.ContainsKey("OutputFolder") -and -not $NoPrompt) {
    Write-Host ""
    Write-Host "Default output folder:"
    Write-Host $requestedOutputFolder
    $customOutput = Read-Host "Press Enter to use that folder, or type a different full output folder path"
    if (-not [string]::IsNullOrWhiteSpace($customOutput)) {
        $requestedOutputFolder = $customOutput.Trim()
    }
}

$OutputFolder = $requestedOutputFolder
Ensure-Directory $OutputFolder

$doCopyRaw = $CopyRawVideo.IsPresent
if (-not $PSBoundParameters.ContainsKey("CopyRawVideo") -and -not $NoPrompt) {
    $value = Read-Host "Copy original source video into raw folder? (Y/n)"
    if ([string]::IsNullOrWhiteSpace($value)) {
        $doCopyRaw = $true
    }
    else {
        $doCopyRaw = $value.Trim() -match '^(y|yes)$'
    }
}

if ([double]::IsNaN($FrameIntervalSeconds)) {
    if ($NoPrompt) {
        $FrameIntervalSeconds = 0.5
    }
    else {
        $FrameIntervalSeconds = Get-InteractiveFrameInterval -DefaultValue 0.5
    }
}

Test-FrameIntervalValue -Value $FrameIntervalSeconds

$bootstrapLog = Join-Path $OutputFolder "_script_bootstrap.log"
$script:CurrentLogFile = $bootstrapLog
"==== Bootstrap started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====" | Set-Content -Path $bootstrapLog -Encoding UTF8
Write-Log "Selected frame interval: $FrameIntervalSeconds seconds"
Write-Log "Output folder root: $OutputFolder"

$masterReadme = Join-Path $OutputFolder "CODEX_MASTER_README.txt"
$summaryCsv = Join-Path $OutputFolder "PROCESSING_SUMMARY.csv"

$videos = @()

if ($InputPath) {
    $videos = Get-VideoFilesFromPath -Path $InputPath
}
else {
    $videos = Get-VideoFilesFromPath -Path $InputFolder

    if ((-not $videos -or $videos.Count -eq 0) -and -not $NoPrompt) {
        Write-Host "No video files found in default input folder:"
        Write-Host $InputFolder
        Write-Host ""
        $manual = Read-Host "Enter a full path to a video file or folder"
        $videos = Get-VideoFilesFromPath -Path $manual
    }
}

if (-not $videos -or $videos.Count -eq 0) {
    throw "No supported video files found to process."
}

if (Test-Path $summaryCsv) {
    Remove-Item $summaryCsv -Force
}

$videosWithAudio = @()
foreach ($video in $videos) {
    try {
        if (Test-VideoHasAudio -FFprobeExe $FFprobePath -VideoPath $video.FullName) {
            $videosWithAudio += $video
        }
    }
    catch {
        Write-Log "Audio probe warning for $($video.FullName): $($_.Exception.Message)" "WARN"
    }
}

if ($videosWithAudio.Count -gt 0) {
    Test-PythonWhisper -PythonCommand $PythonExe
}

$nvencSupported = Test-FFmpegNvencSupport -FFmpegExe $FFmpegPath
$cudaHwaccelSupported = Test-FFmpegCudaHwaccelSupport -FFmpegExe $FFmpegPath
$nvidiaPresent = Test-NvidiaSmiAvailable
$whisperProbe = Get-WhisperExecutionMode -PythonCommand $PythonExe

$canUseFfmpegGpu = $false
if ($nvencSupported -and $cudaHwaccelSupported -and $nvidiaPresent) {
    $canUseFfmpegGpu = $true
}

$canUseWhisperGpu = $false
if ($whisperProbe.WhisperImportOk -and $whisperProbe.TorchImportOk -and $whisperProbe.CudaAvailable) {
    $canUseWhisperGpu = $true
}

Write-Host ""
Write-Host "Resolved tools"
Write-Host "--------------"
Write-Host ("FFmpeg:   {0}" -f $FFmpegPath)
Write-Host ("FFprobe:  {0}" -f $FFprobePath)
Write-Host ("Python:   {0}" -f $PythonExe)
Write-Host ""
Write-Host "Hardware Acceleration Detection"
Write-Host "-------------------------------"
Write-Host ("NVIDIA GPU detected (nvidia-smi): {0}" -f $(if ($nvidiaPresent) { "Yes" } else { "No" }))
Write-Host ("FFmpeg CUDA hwaccel support:     {0}" -f $(if ($cudaHwaccelSupported) { "Yes" } else { "No" }))
Write-Host ("FFmpeg NVENC support:            {0}" -f $(if ($nvencSupported) { "Yes" } else { "No" }))
Write-Host ("Whisper/PyTorch CUDA available:  {0}" -f $(if ($canUseWhisperGpu) { "Yes" } else { "No" }))
if ($whisperProbe.TorchVersion) {
    Write-Host ("PyTorch version:                 {0}" -f $whisperProbe.TorchVersion)
}
if ($whisperProbe.CudaVersion) {
    Write-Host ("PyTorch CUDA version:            {0}" -f $whisperProbe.CudaVersion)
}
if ($whisperProbe.Error) {
    Write-Host ("Whisper probe notes:             {0}" -f $whisperProbe.Error)
}
Write-Host ""
Write-Host ("Proxy path selected:             {0}" -f $(if ($canUseFfmpegGpu) { "GPU preferred with CPU fallback" } else { "CPU fallback" }))
Write-Host ("Frame extraction path selected:  {0}" -f $(if ($canUseFfmpegGpu) { "GPU preferred with CPU fallback" } else { "CPU" }))
Write-Host ("Whisper path selected:           {0}" -f $(if ($canUseWhisperGpu) { "GPU preferred with CPU fallback" } else { "CPU fallback" }))
Write-Host ("Selected frame interval:         {0} seconds" -f $FrameIntervalSeconds)
Write-Host ("Heartbeat interval:              {0} seconds" -f $HeartbeatSeconds)
Write-Host ("Input source:                    {0}" -f $(if ($InputPath) { $InputPath } else { $InputFolder }))
Write-Host ("Output folder:                   {0}" -f $OutputFolder)
Write-Host ""
Write-Host "Videos to process:"
$videos | ForEach-Object { Write-Host " - $($_.FullName)" }
Write-Host ""

$estimate = $null
if (-not $SkipEstimate) {
    $estimate = Get-BestEffortEstimate `
        -Videos $videos `
        -FFmpegExe $FFmpegPath `
        -FFprobeExe $FFprobePath `
        -PythonCommand $PythonExe `
        -ModelName $WhisperModel `
        -LanguageCode $Language `
        -CanUseFfmpegGpu $canUseFfmpegGpu `
        -CanUseWhisperGpu $canUseWhisperGpu `
        -FrameIntervalSeconds $FrameIntervalSeconds
}
else {
    Write-Log "Skipping runtime estimate because -SkipEstimate was requested." "WARN"
}

if ($estimate) {
    Write-Host "Estimated completion for this run"
    Write-Host "---------------------------------"
    Write-Host ("Total media duration:   {0}" -f (Format-DurationHuman $estimate.TotalDurationSeconds))
    Write-Host ("Proxy generation:       {0}" -f (Format-DurationHuman $estimate.ProxyEstimateSeconds))
    Write-Host ("Frame extraction:       {0}" -f (Format-DurationHuman $estimate.FramesEstimateSeconds))
    Write-Host ("Audio extraction:       {0}" -f (Format-DurationHuman $estimate.AudioEstimateSeconds))
    Write-Host ("Whisper transcription:  {0}" -f (Format-DurationHuman $estimate.WhisperEstimateSeconds))
    Write-Host ("Index/build overhead:   {0}" -f (Format-DurationHuman $estimate.IndexEstimateSeconds))
    Write-Host ("Estimated total:        {0}" -f (Format-DurationHuman $estimate.TotalEstimateSeconds))
    Write-Host ""

    if ($estimate.Warnings) {
        foreach ($warning in $estimate.Warnings) {
            Write-Log $warning "WARN"
        }
    }

    $eta = (Get-Date).AddSeconds($estimate.TotalEstimateSeconds)
    Write-Host ("Estimated finish time:  {0}" -f $eta.ToString("yyyy-MM-dd hh:mm:ss tt"))
    Write-Host ""
    Write-Log ("Estimated total runtime: {0}" -f (Format-DurationHuman $estimate.TotalEstimateSeconds))
    Write-Log ("Estimated finish time: {0}" -f $eta.ToString("yyyy-MM-dd hh:mm:ss tt"))
}

$processedItems = @()
$failedItems = @()

foreach ($video in $videos) {
    try {
        $result = Process-Video `
            -VideoPath $video.FullName `
            -BaseOutputFolder $OutputFolder `
            -FFmpegExe $FFmpegPath `
            -FFprobeExe $FFprobePath `
            -PythonCommand $PythonExe `
            -ModelName $WhisperModel `
            -LanguageCode $Language `
            -DoCopyRaw:$doCopyRaw `
            -SummaryCsv $summaryCsv `
            -CanUseFfmpegGpu $canUseFfmpegGpu `
            -CanUseWhisperGpu $canUseWhisperGpu `
            -FrameIntervalSeconds $FrameIntervalSeconds `
            -HeartbeatSeconds $HeartbeatSeconds

        $processedItems += $result
    }
    catch {
        $failedItems += [PSCustomObject]@{
            VideoPath = $video.FullName
            Message   = $_.Exception.Message
        }

        Write-Host ""
        Write-Host ("FAIL {0}" -f $video.FullName) -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        if ($script:CurrentLogFile) {
            Add-Content -Path $script:CurrentLogFile -Value "----- FAILURE -----" -Encoding UTF8
            Add-Content -Path $script:CurrentLogFile -Value $_.Exception.Message -Encoding UTF8
            if ($_.ScriptStackTrace) {
                Add-Content -Path $script:CurrentLogFile -Value $_.ScriptStackTrace -Encoding UTF8
            }
        }
    }
}

New-MasterReadme -MasterReadmePath $masterReadme -OutputRoot $OutputFolder -ProcessedItems $processedItems -FrameIntervalSeconds $FrameIntervalSeconds

Write-Phase -Name "Final Summary" -Detail "Packaging complete"
Write-Host ("Successful packages: {0}" -f $processedItems.Count)
Write-Host ("Failed packages:     {0}" -f $failedItems.Count)
Write-Host ("Output root:         {0}" -f $OutputFolder)
Write-Host ("Master README:       {0}" -f $masterReadme)
Write-Host ("Processing summary:  {0}" -f $summaryCsv)

foreach ($item in $processedItems) {
    Write-Host ("PASS {0}" -f $item.SourceVideoName) -ForegroundColor Green
    Write-Host ("  Output:  {0}" -f $item.OutputPath)
    Write-Host ("  Proxy:   {0}" -f $item.ProxyMode)
    Write-Host ("  Frames:  {0}" -f $item.FrameMode)
    Write-Host ("  Whisper: {0}" -f $item.WhisperMode)
}

foreach ($item in $failedItems) {
    Write-Host ("FAIL {0}" -f $item.VideoPath) -ForegroundColor Red
    Write-Host ("  Error: {0}" -f $item.Message) -ForegroundColor Red
}

if ($failedItems.Count -gt 0 -or $processedItems.Count -eq 0) {
    Write-Log ("FAIL: Processing completed with {0} failure(s)." -f $failedItems.Count) "ERROR"
    throw ("Processing completed with {0} failure(s)." -f $failedItems.Count)
}

Write-Log ("PASS: All {0} video(s) processed successfully. Output root: {1}" -f $processedItems.Count, $OutputFolder)
