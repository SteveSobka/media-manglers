param(
    [Alias("InputUrl")]
    [string]$InputPath,
    [string]$InputFolder = "C:\DATA\TEMP\_AUDIO_INPUT",
    [string]$OutputFolder = "C:\DATA\TEMP\_AUDIO_OUTPUT",
    [string]$FFmpegPath = "D:\APPS\ffmpeg\bin\ffmpeg.exe",
    [string]$PythonExe = "py",
    [string]$YtDlpPath = "yt-dlp",
    [string]$WhisperModel = "base",
    [string]$Language = "",
    [string]$TranslateTo = "",
    [ValidateSet("Local", "AI")]
    [string]$ProcessingMode = "",
    [ValidateSet("Auto", "OpenAI", "Local")]
    [string]$TranslationProvider = "",
    [string]$OpenAiModel = "gpt-5-mini",
    [ValidateSet("Private", "Public")]
    [string]$OpenAiProject = "Private",
    [int]$HeartbeatSeconds = 10,
    [switch]$CopyRawAudio,
    [switch]$IncludeComments,
    [switch]$CreateChatGptZip,
    [switch]$KeepTempFiles,
    [switch]$OpenOutputInExplorer,
    [switch]$NoPrompt,
    [switch]$SkipEstimate,
    [Alias("ShowVersion")]
    [switch]$Version,
    [int]$ChatGptZipMaxMb = 500
)

$ErrorActionPreference = "Stop"
$script:CurrentLogFile = $null
$script:AppName = "Audio Mangler"
$script:FallbackAppVersion = "0.6.0"
$script:LocalAccuracyWhisperModel = "large"
$script:LocalCpuLongWhisperWarningThresholdSeconds = 900
$script:OpenAiPrivateTranslationDefaultModel = "gpt-5-mini"
$script:OpenAiPublicTranslationDefaultModel = "gpt-4o-mini-2024-07-18"
$script:OpenAiTranscriptionModel = "whisper-1"
$script:OpenAiPrivateTranslationApprovedModels = @(
    "gpt-5-mini",
    "gpt-5-mini-2025-08-07",
    "gpt-4.1-mini-2025-04-14",
    "gpt-4o-mini-2024-07-18"
)
$script:OpenAiPublicTranslationApprovedModels = @(
    "gpt-4o-mini-2024-07-18",
    "gpt-4.1-mini-2025-04-14"
)
$script:OpenAiPrivateTranscriptionApprovedModels = @(
    "whisper-1"
)
$script:OpenAiModelDiscoveryCache = @{}
$script:SessionOpenAiApiKey = $null
$script:OpenAiTestModeLogged = $false

function Get-AppVersion {
    if ($script:ResolvedAppVersion) {
        return $script:ResolvedAppVersion
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($PSScriptRoot) {
        $candidates.Add((Join-Path $PSScriptRoot "VERSION"))
    }

    if ($PSScriptRoot) {
        $parentRoot = Split-Path -Path $PSScriptRoot -Parent
        if (-not [string]::IsNullOrWhiteSpace($parentRoot)) {
            $candidates.Add((Join-Path $parentRoot "VERSION"))
        }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate) {
            $value = (Get-Content -LiteralPath $candidate | Select-Object -First 1).Trim()
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $script:ResolvedAppVersion = $value
                return $script:ResolvedAppVersion
            }
        }
    }

    try {
        $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if (-not [string]::IsNullOrWhiteSpace($processPath)) {
            $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($processPath).ProductVersion
            if (-not [string]::IsNullOrWhiteSpace($fileVersion)) {
                $script:ResolvedAppVersion = $fileVersion
                return $script:ResolvedAppVersion
            }
        }
    }
    catch {
    }

    $script:ResolvedAppVersion = $script:FallbackAppVersion
    return $script:ResolvedAppVersion
}

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
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
}

function Test-IsHttpUrl {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri)) {
        return $false
    }

    return $uri.Scheme -in @([System.Uri]::UriSchemeHttp, [System.Uri]::UriSchemeHttps)
}

function Get-HttpUrlsFromText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        ([regex]::Matches($Value, 'https?://\S+')) |
            ForEach-Object { $_.Value.Trim().Trim(',', ';') } |
            Where-Object { Test-IsHttpUrl -Value $_ }
    )
}

function Resolve-DefaultInputOutputFolders {
    param(
        [string]$CurrentInputFolder,
        [string]$CurrentOutputFolder,
        [switch]$InputProvided,
        [switch]$OutputProvided,
        [switch]$NoPrompt
    )

    $cInputDefault = "C:\DATA\TEMP\_AUDIO_INPUT"
    $cOutputDefault = "C:\DATA\TEMP\_AUDIO_OUTPUT"
    $dInputDefault = "D:\DATA\TEMP\_AUDIO_INPUT"
    $dOutputDefault = "D:\DATA\TEMP\_AUDIO_OUTPUT"

    if (-not $InputProvided -and -not $OutputProvided) {
        if ((Test-Path -LiteralPath $cInputDefault) -or (Test-Path -LiteralPath $cOutputDefault)) {
            return [PSCustomObject]@{ InputFolder = $cInputDefault; OutputFolder = $cOutputDefault }
        }

        if ((Test-Path -LiteralPath $dInputDefault) -or (Test-Path -LiteralPath $dOutputDefault)) {
            return [PSCustomObject]@{ InputFolder = $dInputDefault; OutputFolder = $dOutputDefault }
        }

        if ($NoPrompt) {
            return [PSCustomObject]@{ InputFolder = $cInputDefault; OutputFolder = $cOutputDefault }
        }

        Write-Host ""
        Write-Host "No default input/output folders were found on C: or D:." -ForegroundColor Yellow
        Write-Host ("Recommended input folder:  {0}" -f $cInputDefault) -ForegroundColor Cyan
        Write-Host ("Recommended output folder: {0}" -f $cOutputDefault) -ForegroundColor Cyan
        $baseChoice = Read-Host "Press Enter to use C:\DATA\TEMP, or type another base folder"

        if ([string]::IsNullOrWhiteSpace($baseChoice)) {
            return [PSCustomObject]@{ InputFolder = $cInputDefault; OutputFolder = $cOutputDefault }
        }

        $basePath = $baseChoice.Trim()
        return [PSCustomObject]@{
            InputFolder  = Join-Path $basePath "_AUDIO_INPUT"
            OutputFolder = Join-Path $basePath "_AUDIO_OUTPUT"
        }
    }

    $resolvedInput = $CurrentInputFolder
    $resolvedOutput = $CurrentOutputFolder

    if (-not $InputProvided) {
        if ($OutputProvided -and -not [string]::IsNullOrWhiteSpace($CurrentOutputFolder)) {
            $outputParent = Split-Path $CurrentOutputFolder -Parent
            if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
                $resolvedInput = Join-Path $outputParent "_AUDIO_INPUT"
            }
        }
    }

    if (-not $OutputProvided) {
        if ($InputProvided -and -not [string]::IsNullOrWhiteSpace($CurrentInputFolder)) {
            $inputParent = Split-Path $CurrentInputFolder -Parent
            if (-not [string]::IsNullOrWhiteSpace($inputParent)) {
                $resolvedOutput = Join-Path $inputParent "_AUDIO_OUTPUT"
            }
        }
    }

    return [PSCustomObject]@{
        InputFolder  = $resolvedInput
        OutputFolder = $resolvedOutput
    }
}

function Get-YtDlpInstallCommands {
    param([string]$PythonCommand)

    return @(
        "winget install yt-dlp.yt-dlp",
        "$PythonCommand -m pip install -U yt-dlp"
    )
}

function Write-YtDlpInstallGuidance {
    param([string]$PythonCommand)

    Write-Host ""
    Write-Host "yt-dlp is required to download from YouTube or another supported remote media URL." -ForegroundColor Yellow
    Write-Host "Install it with one of these commands:" -ForegroundColor Yellow
    foreach ($command in (Get-YtDlpInstallCommands -PythonCommand $PythonCommand)) {
        Write-Host ("  {0}" -f $command) -ForegroundColor Yellow
    }
    Write-Host ""
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
        Add-Content -LiteralPath $script:CurrentLogFile -Value $line
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
        -FallbackPaths @("D:\APPS\ffmpeg\bin\ffprobe.exe", "C:\APPS\ffmpeg\bin\ffprobe.exe") `
        -ToolName "ffprobe"
}

function Resolve-CommandOrPath {
    param(
        [string]$Value,
        [string]$ToolName
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$ToolName not specified."
    }

    if (Test-Path -LiteralPath $Value) {
        return (Resolve-Path -LiteralPath $Value).ProviderPath
    }

    $command = Get-Command $Value -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return $command.Source
    }

    throw "$ToolName not found. Checked command/path: $Value"
}

function Normalize-UserPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    $normalized = $Path.Trim()

    if ($normalized.Length -ge 2) {
        if (($normalized.StartsWith('"') -and $normalized.EndsWith('"')) -or
            ($normalized.StartsWith("'") -and $normalized.EndsWith("'"))) {
            $normalized = $normalized.Substring(1, $normalized.Length - 2).Trim()
        }
    }

    return $normalized
}

function Resolve-YtDlpInvoker {
    param(
        [string]$PreferredCommand,
        [string]$PythonCommand
    )

    $executableCandidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($PreferredCommand)) {
        $executableCandidates.Add($PreferredCommand)
    }

    foreach ($commandName in @("yt-dlp", "yt-dlp.exe")) {
        if (-not [string]::IsNullOrWhiteSpace($commandName)) {
            $executableCandidates.Add($commandName)
        }
    }

    $userProfile = [Environment]::GetFolderPath("UserProfile")
    $localAppData = [Environment]::GetFolderPath("LocalApplicationData")
    $roamingAppData = [Environment]::GetFolderPath("ApplicationData")
    $fallbackGlobs = @(
        (Join-Path $userProfile "AppData\Roaming\Python\Python*\Scripts\yt-dlp.exe"),
        (Join-Path $localAppData "Programs\Python\Python*\Scripts\yt-dlp.exe"),
        (Join-Path $roamingAppData "Python\Python*\Scripts\yt-dlp.exe")
    )

    foreach ($glob in $fallbackGlobs) {
        $matches = @(Get-ChildItem -Path $glob -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)
        foreach ($match in $matches) {
            $executableCandidates.Add($match.FullName)
        }
    }

    foreach ($candidate in ($executableCandidates | Select-Object -Unique)) {
        try {
            $resolved = Resolve-CommandOrPath -Value $candidate -ToolName "yt-dlp"
            return [PSCustomObject]@{
                FilePath    = $resolved
                Arguments   = @()
                DisplayName = $resolved
            }
        }
        catch {
            Write-Log "yt-dlp command candidate '$candidate' unavailable: $($_.Exception.Message)" "WARN"
        }
    }

    $pythonCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($PythonCommand, "py", "python", "python3")) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $pythonCandidates.Add($candidate)
        }
    }

    foreach ($pythonCandidate in ($pythonCandidates | Select-Object -Unique)) {
        $moduleCheck = Invoke-ExternalCapture `
            -FilePath $pythonCandidate `
            -Arguments @("-m", "yt_dlp", "--version") `
            -StepName "yt-dlp Python module check ($pythonCandidate)" `
            -TimeoutSeconds 60 `
            -IgnoreExitCode

        if ($moduleCheck.ExitCode -eq 0) {
            return [PSCustomObject]@{
                FilePath    = $pythonCandidate
                Arguments   = @("-m", "yt_dlp")
                DisplayName = "$pythonCandidate -m yt_dlp"
            }
        }
    }

    throw "Remote media URLs that are not direct audio files require yt-dlp. Install it with 'winget install yt-dlp.yt-dlp' or 'py -m pip install -U yt-dlp'."
}

function Get-RemoteSourceKind {
    param([string]$SourceUrl)

    $normalized = $SourceUrl.ToLowerInvariant()
    $isYoutube = $normalized -match '^https?://([a-z0-9-]+\.)?(youtube\.com|youtu\.be)/'

    if ($isYoutube -and (
            $normalized -match 'youtube\.com/playlist\?' -or
            ($normalized -match '[?&]list=' -and $normalized -notmatch '[?&]v=' -and $normalized -notmatch 'youtu\.be/')
        )) {
        return "playlist"
    }

    return "url"
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

    if (-not [string]::IsNullOrWhiteSpace($stdout) -and $script:CurrentLogFile) {
        Add-Content -LiteralPath $script:CurrentLogFile -Value "----- STDOUT: $StepName -----"
        Add-Content -LiteralPath $script:CurrentLogFile -Value $stdout
    }

    if (-not [string]::IsNullOrWhiteSpace($stderr) -and $script:CurrentLogFile) {
        Add-Content -LiteralPath $script:CurrentLogFile -Value "----- STDERR: $StepName -----"
        Add-Content -LiteralPath $script:CurrentLogFile -Value $stderr
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
                Add-Content -LiteralPath $script:CurrentLogFile -Value $stdout
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            ($stderr -split "`r?`n") | ForEach-Object {
                if ($_ -ne "") {
                    Write-Host $_ -ForegroundColor Yellow
                }
            }
            if ($script:CurrentLogFile) {
                Add-Content -LiteralPath $script:CurrentLogFile -Value $stderr
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

function Get-SupportedAudioExtensions {
    return @(".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".opus", ".webm", ".mka", ".mp4")
}

function Get-AudioFilesFromDownloadFolder {
    param([string]$FolderPath)

    $supportedExtensions = Get-SupportedAudioExtensions
    return @(
        Get-ChildItem -LiteralPath $FolderPath -File -Recurse |
            Where-Object { $supportedExtensions -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object Name |
            ForEach-Object { $_.FullName }
    )
}

function Get-WebPageAudioCandidates {
    param([string]$SourceUrl)

    $response = Invoke-WebRequest -UseBasicParsing -Uri $SourceUrl
    $baseUri = [System.Uri]$SourceUrl
    $supportedExtensions = Get-SupportedAudioExtensions
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($link in $response.Links) {
        $href = [string]$link.href
        if ([string]::IsNullOrWhiteSpace($href)) {
            continue
        }

        try {
            $absoluteUri = [System.Uri]::new($baseUri, $href)
        }
        catch {
            continue
        }

        $leaf = [System.IO.Path]::GetExtension($absoluteUri.AbsolutePath).ToLowerInvariant()
        if ($supportedExtensions -contains $leaf) {
            [void]$candidates.Add($absoluteUri.AbsoluteUri)
        }
    }

    if ($candidates.Count -eq 0) {
        foreach ($match in ([regex]::Matches($response.Content, 'https?://[^"\''\s>]+\.(mp3|wav|flac|m4a|aac|ogg|opus|webm|mka|mp4)'))) {
            [void]$candidates.Add($match.Value)
        }
    }

    return @(
        $candidates |
            Select-Object -Unique |
            Sort-Object @{
                Expression = { if ($_ -match '(^|[^0-9])64kb([^0-9]|$)') { 1 } else { 0 } }
            }, @{
                Expression = { if ($_ -match '\.mp3($|\?)') { 0 } else { 1 } }
            }, Length
    )
}

function Download-DirectAudioFile {
    param(
        [string]$SourceUrl,
        [string]$SessionFolder,
        [int]$Index = 1
    )

    $uri = [System.Uri]$SourceUrl
    $leaf = [System.IO.Path]::GetFileName($uri.AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        $leaf = "audio_{0:00001}.bin" -f $Index
    }

    $safeLeaf = Get-SafeFolderName -Name $leaf
    $destinationPath = Join-Path $SessionFolder $safeLeaf
    Invoke-WebRequest -UseBasicParsing -Headers @{ "User-Agent" = "Mozilla/5.0" } -Uri $SourceUrl -OutFile $destinationPath
    return $destinationPath
}

function Invoke-RemoteAudioDownload {
    param(
        [string]$SourceUrl,
        [string]$DownloadFolder,
        [psobject]$YtDlpInvoker,
        [switch]$IncludeComments,
        [int]$HeartbeatSeconds = 30
    )

    Ensure-Directory $DownloadFolder

    $sourceKind = Get-RemoteSourceKind -SourceUrl $SourceUrl
    $sessionFolderName = "download-{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
    $sessionFolder = Join-Path $DownloadFolder $sessionFolderName
    Ensure-Directory $sessionFolder

    $urlLeafExtension = [System.IO.Path]::GetExtension(([System.Uri]$SourceUrl).AbsolutePath).ToLowerInvariant()
    if ((Get-SupportedAudioExtensions) -contains $urlLeafExtension) {
        try {
            $directAudioPath = Download-DirectAudioFile -SourceUrl $SourceUrl -SessionFolder $sessionFolder
            Write-Log ("Remote direct-audio downloaded. Items: 1. Cache folder: {0}" -f $sessionFolder)
            return [PSCustomObject]@{
                SourceKind         = "direct-audio"
                DownloadRoot       = $sessionFolder
                DownloadedPaths    = @($directAudioPath)
                InfoJsonByMediaPath = @{}
            }
        }
        catch {
            if (-not $YtDlpInvoker) {
                throw
            }

            Write-Log ("Direct audio download fallback failed for {0}: {1}. Trying yt-dlp instead." -f $SourceUrl, $_.Exception.Message) "WARN"
        }
    }

    if (-not $YtDlpInvoker) {
        if ($sourceKind -eq "playlist") {
            throw "yt-dlp is required to download playlist URLs."
        }

        $pageCandidates = @(Get-WebPageAudioCandidates -SourceUrl $SourceUrl)
        if ($pageCandidates.Count -gt 0) {
            $selectedCandidate = $pageCandidates[0]
            Write-Log ("yt-dlp not available. Falling back to discovered audio link: {0}" -f $selectedCandidate) "WARN"
            $fallbackAudioPath = Download-DirectAudioFile -SourceUrl $selectedCandidate -SessionFolder $sessionFolder
            Write-Log ("Remote page-audio downloaded. Items: 1. Cache folder: {0}" -f $sessionFolder)
            return [PSCustomObject]@{
                SourceKind         = "page-audio"
                DownloadRoot       = $sessionFolder
                DownloadedPaths    = @($fallbackAudioPath)
                InfoJsonByMediaPath = @{}
            }
        }

        throw "yt-dlp is required to download this remote source."
    }

    $outputTemplate = if ($sourceKind -eq "playlist") {
        "%(playlist_index)05d - %(title).120B [%(id)s].%(ext)s"
    }
    else {
        "%(title).120B [%(id)s].%(ext)s"
    }

    $playlistArguments = if ($sourceKind -eq "playlist") {
        @("--yes-playlist", "--ignore-errors")
    }
    else {
        @("--no-playlist")
    }

    $result = Invoke-ExternalStreaming `
        -FilePath $YtDlpInvoker.FilePath `
        -Arguments ($YtDlpInvoker.Arguments + @(
            "--newline",
            "--restrict-filenames",
            "--print", "after_move:filepath",
            "-P", $sessionFolder,
            "-o", $outputTemplate,
            "--format", "ba/b"
        ) + $(if ($IncludeComments) { @("--write-info-json", "--write-comments") } else { @() }) + $playlistArguments + @($SourceUrl)) `
        -StepName ("yt-dlp download ({0})" -f $sourceKind) `
        -IgnoreExitCode `
        -HeartbeatSeconds $HeartbeatSeconds `
        -TimeoutSeconds 7200

    $downloadedPaths = @()
    foreach ($line in ($result.StdOut -split "`r?`n")) {
        $candidate = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            $item = Get-Item -LiteralPath $candidate
            if (-not $item.PSIsContainer -and (Get-SupportedAudioExtensions) -contains $item.Extension.ToLowerInvariant()) {
                $downloadedPaths += $item.FullName
            }
        }
    }

    if ($downloadedPaths.Count -eq 0) {
        $downloadedPaths = Get-AudioFilesFromDownloadFolder -FolderPath $sessionFolder
    }

    if ($downloadedPaths.Count -eq 0 -and $sourceKind -ne "playlist") {
        try {
            $pageCandidates = @(Get-WebPageAudioCandidates -SourceUrl $SourceUrl)
            if ($pageCandidates.Count -gt 0) {
                $selectedCandidate = $pageCandidates[0]
                Write-Log ("yt-dlp could not resolve audio from the page directly. Falling back to discovered audio link: {0}" -f $selectedCandidate) "WARN"
                $downloadedPaths = @(
                    Download-DirectAudioFile -SourceUrl $selectedCandidate -SessionFolder $sessionFolder
                )
                $sourceKind = "page-audio"
            }
        }
        catch {
            Write-Log ("Page audio fallback failed for {0}: {1}" -f $SourceUrl, $_.Exception.Message) "WARN"
        }
    }

    if ($downloadedPaths.Count -eq 0) {
        if ($result.ExitCode -ne 0) {
            throw ("yt-dlp audio download ({0}) failed with exit code {1}. See script_run.log." -f $sourceKind, $result.ExitCode)
        }

        throw "Remote source finished without producing a supported local audio file in $sessionFolder"
    }

    if ($result.ExitCode -ne 0) {
        if ($sourceKind -eq "playlist") {
            Write-Log ("yt-dlp reported some playlist entries as unavailable or inaccessible. Continuing with {0} downloaded audio file(s)." -f $downloadedPaths.Count) "WARN"
        }
        else {
            Write-Log ("yt-dlp reported an issue but fallback audio files were recovered. Continuing with {0} downloaded file(s)." -f $downloadedPaths.Count) "WARN"
        }
    }

    Write-Log ("Remote {0} downloaded. Items: {1}. Cache folder: {2}" -f $sourceKind, $downloadedPaths.Count, $sessionFolder)

    $infoJsonByMediaPath = @{}
    foreach ($downloadedPath in $downloadedPaths) {
        $basePath = Join-Path ([System.IO.Path]::GetDirectoryName($downloadedPath)) ([System.IO.Path]::GetFileNameWithoutExtension($downloadedPath))
        $infoJsonPath = "$basePath.info.json"
        if (Test-Path -LiteralPath $infoJsonPath) {
            $infoJsonByMediaPath[$downloadedPath] = $infoJsonPath
        }
    }

    return [PSCustomObject]@{
        SourceKind      = $sourceKind
        DownloadRoot    = $sessionFolder
        DownloadedPaths = $downloadedPaths
        InfoJsonByMediaPath = $infoJsonByMediaPath
    }
}

function Export-CommentsArtifactsFromInfoJson {
    param(
        [string]$InfoJsonPath,
        [string]$CommentsFolder
    )

    if ([string]::IsNullOrWhiteSpace($InfoJsonPath) -or -not (Test-Path -LiteralPath $InfoJsonPath)) {
        return $null
    }

    $payload = Get-Content -LiteralPath $InfoJsonPath -Raw | ConvertFrom-Json
    $comments = @($payload.comments)
    if ($comments.Count -eq 0) {
        return $null
    }

    Ensure-Directory $CommentsFolder

    $commentsJsonPath = Join-Path $CommentsFolder "comments.json"
    $commentsTextPath = Join-Path $CommentsFolder "comments.txt"

    $normalizedComments = @()
    $textLines = New-Object System.Collections.Generic.List[string]
    [void]$textLines.Add("Public comments export")
    [void]$textLines.Add("======================")
    [void]$textLines.Add("")

    if ($payload.title) {
        [void]$textLines.Add(("Title: {0}" -f $payload.title))
    }
    if ($payload.webpage_url) {
        [void]$textLines.Add(("Source: {0}" -f $payload.webpage_url))
    }
    [void]$textLines.Add(("Comments exported: {0}" -f $comments.Count))
    [void]$textLines.Add("")

    $index = 0
    foreach ($comment in $comments) {
        $index += 1
        $author = [string]$comment.author
        $text = [string]$comment.text
        $timestamp = [string]$comment.timestamp
        $likeCount = [string]$comment.like_count
        $normalizedComments += [PSCustomObject]@{
            id         = [string]$comment.id
            author     = $author
            text       = $text
            timestamp  = $timestamp
            like_count = $likeCount
            parent     = [string]$comment.parent
            is_favorited = [string]$comment.is_favorited
        }

        [void]$textLines.Add(("[{0}] {1}" -f $index, $(if ([string]::IsNullOrWhiteSpace($author)) { "Unknown author" } else { $author })))
        if (-not [string]::IsNullOrWhiteSpace($timestamp)) {
            [void]$textLines.Add(("Date: {0}" -f $timestamp))
        }
        if (-not [string]::IsNullOrWhiteSpace($likeCount)) {
            [void]$textLines.Add(("Likes: {0}" -f $likeCount))
        }
        [void]$textLines.Add("Comment:")
        [void]$textLines.Add($(if ([string]::IsNullOrWhiteSpace($text)) { "[empty]" } else { $text.Trim() }))
        [void]$textLines.Add("")
    }

    [PSCustomObject]@{
        title         = [string]$payload.title
        webpage_url   = [string]$payload.webpage_url
        extractor_key = [string]$payload.extractor_key
        comment_count = $normalizedComments.Count
        comments      = $normalizedComments
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $commentsJsonPath -Encoding UTF8

    $textLines | Set-Content -LiteralPath $commentsTextPath -Encoding UTF8

    return [PSCustomObject]@{
        CommentsFolder   = $CommentsFolder
        CommentsJsonPath = $commentsJsonPath
        CommentsTextPath = $commentsTextPath
        CommentCount     = $normalizedComments.Count
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

function Get-InteractiveInputSource {
    param(
        [string]$DefaultInputFolder,
        [string]$YtDlpCommand,
        [string]$PythonCommand
    )

    while ($true) {
        Write-Host ""
        Write-Host "Default local input source:" -ForegroundColor Cyan
        Write-Host $DefaultInputFolder -ForegroundColor Cyan
        Write-Host "Choose an input method:" -ForegroundColor Cyan
        Write-Host "  1. Paste audio, YouTube, or playlist URLs" -ForegroundColor Cyan
        Write-Host ("  2. Use this folder: {0}" -f $DefaultInputFolder) -ForegroundColor Cyan
        Write-Host "  3. Paste a full local audio file path or folder path" -ForegroundColor Cyan
        Write-Host "Press Enter for 3, or type Q to quit." -ForegroundColor Cyan
        $inputChoice = Read-Host "Enter 1, 2, 3, or Q"

        if ([string]::IsNullOrWhiteSpace($inputChoice)) {
            $inputChoice = "3"
        }

        $inputChoice = $inputChoice.Trim()

        if ($inputChoice -match '^(q|quit)$') {
            throw "User canceled at input selection."
        }

        if ($inputChoice -eq "1") {
            Write-Host "Paste text containing one or more audio, video, or playlist URLs." -ForegroundColor Cyan
            Write-Host "Type DONE on its own line when the paste is complete." -ForegroundColor Cyan

            $remoteInputs = New-Object System.Collections.Generic.List[string]
            $capturedLines = New-Object System.Collections.Generic.List[string]
            $duplicateInputs = New-Object System.Collections.Generic.List[string]
            $lineNumber = 1

            while ($true) {
                $prompt = if ($lineNumber -eq 1) { "Paste line 1" } else { "Next line" }
                $remoteInput = Read-Host $prompt

                if (-not [string]::IsNullOrWhiteSpace($remoteInput) -and $remoteInput.Trim().ToUpperInvariant() -eq "DONE") {
                    break
                }

                [void]$capturedLines.Add($remoteInput)
                $lineNumber += 1
            }

            $parsedUrls = @(Get-HttpUrlsFromText -Value ($capturedLines -join "`n"))
            if ($parsedUrls.Count -eq 0) {
                Write-Host "No valid http/https URLs were found in that pasted text." -ForegroundColor Yellow
                continue
            }

            foreach ($parsedUrl in $parsedUrls) {
                if ($remoteInputs.Contains($parsedUrl)) {
                    if (-not $duplicateInputs.Contains($parsedUrl)) {
                        [void]$duplicateInputs.Add($parsedUrl)
                    }
                    continue
                }

                [void]$remoteInputs.Add($parsedUrl)
            }

            if ($duplicateInputs.Count -gt 0) {
                foreach ($duplicateUrl in $duplicateInputs) {
                    Write-Log "Ignoring duplicate remote URL: $duplicateUrl" "WARN"
                }
            }

            Write-Host ("Captured {0} unique remote URL(s)." -f $remoteInputs.Count) -ForegroundColor Cyan

            foreach ($remoteUrl in $remoteInputs) {
                $sourceKind = Get-RemoteSourceKind -SourceUrl $remoteUrl
                if ($sourceKind -eq "playlist") {
                    Write-Host "Playlist detected. The script will download each item in the playlist before packaging." -ForegroundColor Cyan
                }
            }

            return @($remoteInputs)
        }

        if ($inputChoice -eq "2") {
            return $DefaultInputFolder
        }

        if ($inputChoice -eq "3") {
            $customInput = Read-Host "Paste a full local audio file path or folder path"
            if ([string]::IsNullOrWhiteSpace($customInput)) {
                Write-Host "A local audio file path or folder path is required for option 3." -ForegroundColor Yellow
                continue
            }

            return (Normalize-UserPath -Path $customInput)
        }

        Write-Host "Invalid choice. Enter 1, 2, 3, or Q." -ForegroundColor Yellow
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

function Test-LocalWhisperLongCpuRunRisk {
    param(
        [string]$ModelName,
        [bool]$CanUseWhisperGpu,
        [double]$DurationSeconds
    )

    if ($CanUseWhisperGpu) {
        return $false
    }

    if ($DurationSeconds -lt $script:LocalCpuLongWhisperWarningThresholdSeconds) {
        return $false
    }

    $normalizedModel = if ([string]::IsNullOrWhiteSpace($ModelName)) {
        ""
    }
    else {
        $ModelName.Trim().ToLowerInvariant()
    }

    return (
        $normalizedModel -eq "large" -or
        $normalizedModel.StartsWith("large-") -or
        $normalizedModel.StartsWith("large.") -or
        $normalizedModel.StartsWith("large_")
    )
}

function Write-LocalWhisperLongCpuRunWarning {
    param(
        [string]$ModelName,
        [double]$DurationSeconds
    )

    $durationLabel = if ($DurationSeconds -gt 0) {
        Format-DurationHuman -Seconds $DurationSeconds
    }
    else {
        "long media"
    }

    Write-Log ("This Local run is using Whisper model '{0}' on CPU for about {1}. Longer CPU-only Local runs with 'large' can exceed the current 1800-second Whisper watchdog before transcription finishes. If that happens, rerun with GPU, split the media, or choose a smaller -WhisperModel." -f $ModelName, $durationLabel) "WARN"
}

function Get-AudioFilesFromPath {
    param([string]$Path)

    $extensions = Get-SupportedAudioExtensions
    $Path = Normalize-UserPath -Path $Path

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Path not found: $Path"
    }

    $item = Get-Item -LiteralPath $Path

    if ($item.PSIsContainer) {
        return @(Get-ChildItem -LiteralPath $Path -File | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)
    }

    if ($extensions -notcontains $item.Extension.ToLowerInvariant()) {
        throw "Unsupported audio file type: $($item.FullName)"
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
        [string]$AudioFileName,
        [string]$RawPresent,
        [string]$ProcessingModeSummary,
        [string]$OpenAiProjectSummary,
        [string]$TranscriptionPathDetails,
        [string]$DetectedLanguage,
        [string[]]$TranslationTargets,
        [string]$TranslationPathDetails,
        [string]$CommentsSummary,
        [string]$PackageStatus = "SUCCESS",
        [string]$TranslationStatus = "",
        [string]$TranslationNotes = "",
        [string]$NextSteps = ""
    )

@"
README_FOR_CODEX

This folder contains an Audio Mangler review package for:
$AudioFileName

What is included:
- raw\                            original source audio (only if you chose to keep a copy)
- audio\review_audio.mp3          clean listening copy for review
- transcript\transcript_original.srt / .json / .txt
- translations\<lang>\transcript.srt / .json / .txt when translation was requested
- comments\comments.txt / .json   public comments export when available and requested
- segment_index.csv               timestamp index for the original transcript
- script_run.log                  processing log, including raw OpenAI error details when available

A good review order:
1. Start with transcript\transcript_original.txt for the quick read.
2. Use transcript\transcript_original.srt or segment_index.csv when you need timestamps.
3. Open translations\<lang>\ only if you asked for translated text.
4. Use audio\review_audio.mp3 when tone, pronunciation, or emphasis matters.
5. Check comments\ if public source comments were included for extra context.

Notes:
- Package status: $(if ($PackageStatus -eq "PARTIAL_SUCCESS") { "partial success" } else { "success" })
- Processing mode used: $(if ([string]::IsNullOrWhiteSpace($ProcessingModeSummary)) { "Local" } else { $ProcessingModeSummary })
- AI project mode: $(if ([string]::IsNullOrWhiteSpace($OpenAiProjectSummary)) { "not applicable (Local mode)" } else { $OpenAiProjectSummary })
- Transcription path used: $(if ([string]::IsNullOrWhiteSpace($TranscriptionPathDetails)) { "none" } else { $TranscriptionPathDetails })
- Detected source language: $DetectedLanguage
- Translation targets: $(if ($TranslationTargets -and $TranslationTargets.Count -gt 0) { $TranslationTargets -join ", " } else { "none" })
- Translation status: $(if ([string]::IsNullOrWhiteSpace($TranslationStatus)) { "not requested" } else { $TranslationStatus })
- Translation path used: $(if ([string]::IsNullOrWhiteSpace($TranslationPathDetails)) { "none" } else { $TranslationPathDetails })
- Translation notes: $(if ([string]::IsNullOrWhiteSpace($TranslationNotes)) { "none" } else { $TranslationNotes })
- Next steps: $(if ([string]::IsNullOrWhiteSpace($NextSteps)) { "none" } else { $NextSteps })
- Comments: $(if ([string]::IsNullOrWhiteSpace($CommentsSummary)) { "not included" } else { $CommentsSummary })
- Raw audio present: $RawPresent
"@ | Set-Content -LiteralPath $ReadmePath -Encoding UTF8
}

function New-ChatGptReadme {
    param(
        [string]$ReadmePath,
        [string]$SourceAudioName,
        [bool]$AudioIncluded,
        [string[]]$TranslationTargets,
        [bool]$CommentsIncluded
    )

@"
CHATGPT_REVIEW_PACKAGE

Source audio:
$SourceAudioName

Package contents:
- transcript\transcript_original.srt
- transcript\transcript_original.json
- transcript\transcript_original.txt
- segment_index.csv
$(if ($TranslationTargets -and $TranslationTargets.Count -gt 0) { "- translations\<lang>\transcript.*" } else { "- no translated transcript files were requested" })
$(if ($CommentsIncluded) { "- comments\comments.txt and comments\comments.json" } else { "- no public comments export is included" })
$(if ($AudioIncluded) { "- audio\review_audio.mp3" } else { "- review audio omitted to stay under upload size limits" })

Suggested prompts:
1) Ask for a summary of the original transcript first.
2) Ask ChatGPT to use segment_index.csv when it references timestamps.
3) If translations are included, ask it to compare the original and translated wording.
4) If comments are included, ask it whether the public reaction adds useful context.
5) If review audio is included, ask it to cross-check pronunciation or emphasis.
"@ | Set-Content -LiteralPath $ReadmePath -Encoding UTF8
}

function Get-PathSizeBytes {
    param([string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return [int64]0
    }

    if (Test-Path -LiteralPath $LiteralPath -PathType Container) {
        $measured = (Get-ChildItem -LiteralPath $LiteralPath -File -Recurse | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $measured) {
            return [int64]0
        }

        return [int64]$measured
    }

    return [int64](Get-Item -LiteralPath $LiteralPath).Length
}

function New-ChatGptFrameIndex {
    param(
        [string]$SourceFrameIndexCsv,
        [string]$DestinationFrameIndexCsv,
        [array]$SelectedFrames
    )

    $selectedNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($frame in $SelectedFrames) {
        [void]$selectedNames.Add($frame.Name)
    }

    $rows = @(Import-Csv -LiteralPath $SourceFrameIndexCsv | Where-Object { $selectedNames.Contains($_.filename) })
    if ($rows.Count -eq 0) {
        throw "No matching frame index rows were found for the selected ChatGPT frame subset."
    }

    $rows | Export-Csv -LiteralPath $DestinationFrameIndexCsv -NoTypeInformation -Encoding UTF8
}

function New-ChatGptZipPackage {
    param(
        [psobject]$ProcessedItem,
        [int]$MaxSizeMb = 500
    )

    $maxBytes = [int64]$MaxSizeMb * 1MB
    $transcriptFolder = Join-Path $ProcessedItem.OutputPath "transcript"
    $translationsFolder = Join-Path $ProcessedItem.OutputPath "translations"
    $commentsFolder = Join-Path $ProcessedItem.OutputPath "comments"
    $segmentIndexCsv = Join-Path $ProcessedItem.OutputPath "segment_index.csv"
    $audioFile = Join-Path $ProcessedItem.OutputPath "audio\review_audio.mp3"
    $zipPath = Join-Path $ProcessedItem.OutputPath "chatgpt_review_package.zip"
    $requiredPaths = @($transcriptFolder, $segmentIndexCsv)

    foreach ($path in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Cannot build ChatGPT zip because required item is missing: $path"
        }
    }

    if (Test-Path -LiteralPath $translationsFolder) {
        $requiredPaths += $translationsFolder
    }
    if (Test-Path -LiteralPath $commentsFolder) {
        $requiredPaths += $commentsFolder
    }

    $nonAudioBaseBytes = [int64]0
    foreach ($path in $requiredPaths) {
        $nonAudioBaseBytes += Get-PathSizeBytes -LiteralPath $path
    }

    $audioBytes = if (Test-Path -LiteralPath $audioFile) { [int64](Get-Item -LiteralPath $audioFile).Length } else { [int64]0 }

    $tempRoot = Join-Path $ProcessedItem.OutputPath "_chatgpt_zip_temp"
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
    Ensure-Directory $tempRoot

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        foreach ($includeAudio in @($true, $false)) {
            if ($includeAudio -and $audioBytes -gt 0 -and (($nonAudioBaseBytes + $audioBytes) -gt $maxBytes)) {
                continue
            }

            if (Test-Path -LiteralPath $zipPath) {
                Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            }

            $stagingRoot = Join-Path $tempRoot "chatgpt_review"
            if (Test-Path -LiteralPath $stagingRoot) {
                Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
            Ensure-Directory $stagingRoot

            Copy-Item -LiteralPath $transcriptFolder -Destination (Join-Path $stagingRoot "transcript") -Recurse -Force
            if (Test-Path -LiteralPath $translationsFolder) {
                Copy-Item -LiteralPath $translationsFolder -Destination (Join-Path $stagingRoot "translations") -Recurse -Force
            }
            if (Test-Path -LiteralPath $commentsFolder) {
                Copy-Item -LiteralPath $commentsFolder -Destination (Join-Path $stagingRoot "comments") -Recurse -Force
            }

            Copy-Item -LiteralPath $segmentIndexCsv -Destination (Join-Path $stagingRoot "segment_index.csv") -Force

            if ($includeAudio -and $audioBytes -gt 0) {
                Ensure-Directory (Join-Path $stagingRoot "audio")
                Copy-Item -LiteralPath $audioFile -Destination (Join-Path $stagingRoot "audio\review_audio.mp3") -Force
            }

            $chatGptReadme = Join-Path $stagingRoot "README_FOR_CHATGPT.txt"
            New-ChatGptReadme `
                -ReadmePath $chatGptReadme `
                -SourceAudioName $ProcessedItem.SourceAudioName `
                -AudioIncluded:$($includeAudio -and $audioBytes -gt 0) `
                -TranslationTargets $ProcessedItem.TranslationTargets `
                -CommentsIncluded:(Test-Path -LiteralPath $commentsFolder)

            [System.IO.Compression.ZipFile]::CreateFromDirectory(
                $stagingRoot,
                $zipPath,
                [System.IO.Compression.CompressionLevel]::Optimal,
                $false
            )

            $zipSize = (Get-Item -LiteralPath $zipPath).Length
            if ($zipSize -le $maxBytes) {
                return [PSCustomObject]@{
                    ZipPath       = $zipPath
                    ZipSizeMb     = [math]::Round($zipSize / 1MB, 2)
                    AudioIncluded = ($includeAudio -and $audioBytes -gt 0)
                }
            }

            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }

        throw "ChatGPT zip exceeded $MaxSizeMb MB even after omitting review audio."
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-MasterReadme {
    param(
        [string]$MasterReadmePath,
        [string]$OutputRoot,
        [array]$ProcessedItems
    )

    $lines = @()
    $lines += "CODEX_MASTER_README"
    $lines += ""
    $lines += "This folder contains one Audio Mangler package per processed source item."
    $lines += ""
    $lines += "Output root:"
    $lines += $OutputRoot
    $lines += ""
    $lines += "Typical package contents:"
    $lines += "- audio\review_audio.mp3"
    $lines += "- transcript\transcript_original.srt / .json / .txt"
    $lines += "- translations\<lang>\transcript.* when requested"
    $lines += "- comments\comments.* when available and requested"
    $lines += "- segment_index.csv"
    $lines += "- README_FOR_CODEX.txt"
    $lines += "- script_run.log (includes raw OpenAI error details when available)"
    $lines += ""
    $lines += "Processed packages:"
    foreach ($item in $ProcessedItems) {
        $packageSuffix = if ($item.PackageStatus -eq "PARTIAL_SUCCESS") { " (partial success)" } else { "" }
        $lines += "- $($item.OutputFolderName)  <=  $($item.SourceAudioName)$packageSuffix"
    }

    $lines | Set-Content -LiteralPath $MasterReadmePath -Encoding UTF8
}

function Add-SummaryRow {
    param(
        [string]$SummaryCsv,
        [string]$SourceAudio,
        [string]$OutputFolderName,
        [string]$OutputPath,
        [string]$AudioFile,
        [string]$OriginalTranscriptSrt,
        [string]$OriginalTranscriptJson,
        [string]$OriginalTranscriptText,
        [string]$SegmentIndexCsv,
        [string]$RawCopied,
        [string]$DetectedLanguage,
        [string]$ProcessingModeSummary,
        [string]$OpenAiProjectSummary,
        [string]$TranscriptionPath,
        [string]$TranslationTargets,
        [string]$TranslationPath,
        [string]$CommentsText,
        [string]$CommentsJson,
        [string]$CommentsSummary,
        [string]$WhisperMode,
        [string]$PackageStatus,
        [string]$TranslationStatus,
        [string]$TranslationNotes,
        [string]$NextSteps
    )

    $row = [PSCustomObject]@{
        source_audio             = $SourceAudio
        output_folder_name       = $OutputFolderName
        output_path              = $OutputPath
        review_audio             = $AudioFile
        transcript_original_srt  = $OriginalTranscriptSrt
        transcript_original_json = $OriginalTranscriptJson
        transcript_original_txt  = $OriginalTranscriptText
        segment_index_csv        = $SegmentIndexCsv
        raw_copied               = $RawCopied
        detected_language        = $DetectedLanguage
        processing_mode          = $ProcessingModeSummary
        openai_project           = $OpenAiProjectSummary
        transcription_path       = $TranscriptionPath
        translation_targets      = $TranslationTargets
        translation_path         = $TranslationPath
        translation_provider     = $TranslationPath
        package_status           = $PackageStatus
        translation_status       = $TranslationStatus
        translation_notes        = $TranslationNotes
        next_steps               = $NextSteps
        comments_text            = $CommentsText
        comments_json            = $CommentsJson
        comments_summary         = $CommentsSummary
        whisper_mode             = $WhisperMode
    }

    if (-not (Test-Path $SummaryCsv)) {
        $row | Export-Csv -LiteralPath $SummaryCsv -NoTypeInformation -Encoding UTF8
    }
    else {
        $row | Export-Csv -LiteralPath $SummaryCsv -NoTypeInformation -Encoding UTF8 -Append
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
        [ValidateSet("transcribe","translate")]
        [string]$Task = "transcribe",
        [string]$JsonName = "transcript_original.json",
        [string]$SrtName = "transcript_original.srt",
        [string]$TextName = "transcript_original.txt",
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
task_name = sys.argv[7]
json_name = sys.argv[8]
srt_name = sys.argv[9]
text_name = sys.argv[10]

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
    log(f"[PY] Starting {task_name} on {device_name}...")
    result = model.transcribe(
        audio_path,
        language=language_code if language_code else None,
        task=task_name,
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

    srt_path = os.path.join(output_dir, srt_name)
    json_path = os.path.join(output_dir, json_name)
    text_path = os.path.join(output_dir, text_name)

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    with open(text_path, "w", encoding="utf-8") as f:
        segments = result.get("segments") or []
        for seg in segments:
            text = (seg.get("text") or "").strip()
            if text:
                f.write(text + "\n")

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
        "text_path": text_path,
        "language": result.get("language", ""),
        "segments_count": len(result.get("segments") or []),
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
                $PreferGpu.ToString(),
                $Task,
                $JsonName,
                $SrtName,
                $TextName
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
            Device        = [string]$parsed.device
            Fp16          = [bool]$parsed.fp16
            JsonPath      = [string]$parsed.json_path
            SrtPath       = [string]$parsed.srt_path
            TextPath      = [string]$parsed.text_path
            Language      = [string]$parsed.language
            SegmentsCount = [int]$parsed.segments_count
            GpuError      = [string]$parsed.gpu_error
        }
    }
    finally {
        if (Test-Path $tempPy) {
            Remove-Item $tempPy -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-OpenAiAudioTranscriptionRequest {
    param(
        [string]$AudioPath,
        [string]$LanguageCode,
        [string]$Model = ""
    )

    Add-Type -AssemblyName System.Net.Http
    $apiKey = Get-OpenAiApiKey -Required -ProviderLabel "OpenAI transcription"
    $endpoint = "https://api.openai.com/v1/audio/transcriptions"
    $resolvedModel = if ([string]::IsNullOrWhiteSpace($Model)) { $script:OpenAiTranscriptionModel } else { $Model.Trim() }
    $httpClient = New-Object System.Net.Http.HttpClient
    $httpClient.Timeout = [System.TimeSpan]::FromMinutes(20)
    $httpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $apiKey)

    $fileStream = [System.IO.File]::OpenRead($AudioPath)
    $form = New-Object System.Net.Http.MultipartFormDataContent

    try {
        $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("audio/mpeg")
        $form.Add($fileContent, "file", [System.IO.Path]::GetFileName($AudioPath))
        $form.Add((New-Object System.Net.Http.StringContent($resolvedModel, [System.Text.Encoding]::UTF8)), "model")
        $form.Add((New-Object System.Net.Http.StringContent("verbose_json", [System.Text.Encoding]::UTF8)), "response_format")

        if (-not [string]::IsNullOrWhiteSpace($LanguageCode)) {
            $form.Add((New-Object System.Net.Http.StringContent($LanguageCode.Trim(), [System.Text.Encoding]::UTF8)), "language")
        }

        $response = $httpClient.PostAsync($endpoint, $form).GetAwaiter().GetResult()
        $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $requestId = ""
            try {
                $requestId = ($response.Headers.GetValues("x-request-id") | Select-Object -First 1)
            }
            catch {
            }

            $normalizedResponseBody = Normalize-OpenAiResponseText -Text $responseText
            if (-not [string]::IsNullOrWhiteSpace($normalizedResponseBody)) {
                Write-Log ("OpenAI raw response body for transcription: {0}" -f $normalizedResponseBody) "WARN"
            }

            $errorText = if ([string]::IsNullOrWhiteSpace($normalizedResponseBody)) {
                ("OpenAI transcription failed with HTTP {0} {1}." -f ([int]$response.StatusCode), [string]$response.ReasonPhrase)
            }
            else {
                ("OpenAI transcription failed with HTTP {0} {1}. {2}" -f ([int]$response.StatusCode), [string]$response.ReasonPhrase, $normalizedResponseBody)
            }

            if (-not [string]::IsNullOrWhiteSpace($requestId)) {
                $errorText = ("{0} request_id={1}" -f $errorText, $requestId)
            }

            throw $errorText
        }

        return ($responseText | ConvertFrom-Json)
    }
    finally {
        if ($form) {
            $form.Dispose()
        }
        if ($fileStream) {
            $fileStream.Dispose()
        }
        if ($httpClient) {
            $httpClient.Dispose()
        }
    }
}

function New-OpenAiTranscriptionChunkPlan {
    param(
        [string]$AudioPath,
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [int]$HeartbeatSeconds = 10
    )

    $maxUploadBytes = 24MB
    $audioItem = Get-Item -LiteralPath $AudioPath
    $durationSeconds = Get-VideoDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $AudioPath
    if ($audioItem.Length -le $maxUploadBytes) {
        return [PSCustomObject]@{
            TempRoot = ""
            Chunks   = @(
                [PSCustomObject]@{
                    Path            = $AudioPath
                    StartSeconds    = 0.0
                    DurationSeconds = $durationSeconds
                }
            )
        }
    }

    if ($durationSeconds -le 0) {
        throw "Could not determine audio duration for OpenAI transcription chunking."
    }

    $bytesPerSecond = [double]$audioItem.Length / [Math]::Max($durationSeconds, 1.0)
    $dynamicChunkSeconds = [Math]::Floor(($maxUploadBytes * 0.9) / [Math]::Max($bytesPerSecond, 1.0))
    $chunkSeconds = [int][Math]::Min(600, [Math]::Max(60, $dynamicChunkSeconds))
    $tempRoot = Join-Path $env:TEMP ("openai_transcription_chunks_" + [guid]::NewGuid().ToString())
    Ensure-Directory $tempRoot

    $chunks = New-Object System.Collections.Generic.List[object]
    $chunkIndex = 0
    for ($startSeconds = 0.0; $startSeconds -lt $durationSeconds; $startSeconds += $chunkSeconds) {
        $chunkIndex += 1
        $remainingSeconds = [Math]::Max(0.0, ($durationSeconds - $startSeconds))
        $currentDuration = [Math]::Min([double]$chunkSeconds, $remainingSeconds)
        $chunkPath = Join-Path $tempRoot ("chunk_{0:D3}.mp3" -f $chunkIndex)
        $startText = $startSeconds.ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
        $durationText = $currentDuration.ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)

        $result = Invoke-ExternalCapture `
            -FilePath $FFmpegExe `
            -Arguments @("-y", "-ss", $startText, "-t", $durationText, "-i", $AudioPath, "-vn", "-c:a", "libmp3lame", "-b:a", "192k", $chunkPath) `
            -StepName ("OpenAI transcription chunk {0}" -f $chunkIndex) `
            -HeartbeatSeconds $HeartbeatSeconds

        if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $chunkPath)) {
            throw ("OpenAI transcription chunk {0} could not be created." -f $chunkIndex)
        }

        $chunkItem = Get-Item -LiteralPath $chunkPath
        if ($chunkItem.Length -gt $maxUploadBytes) {
            throw ("OpenAI transcription chunk {0} is still larger than the upload limit." -f $chunkIndex)
        }

        [void]$chunks.Add([PSCustomObject]@{
                Path            = $chunkPath
                StartSeconds    = $startSeconds
                DurationSeconds = $currentDuration
            })
    }

    return [PSCustomObject]@{
        TempRoot = $tempRoot
        Chunks   = $chunks.ToArray()
    }
}

function Invoke-OpenAiWhisperTranscript {
    param(
        [string]$AudioPath,
        [string]$TranscriptFolder,
        [string]$LanguageCode,
        [string]$Model = "",
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [string]$JsonName = "transcript_original.json",
        [string]$SrtName = "transcript_original.srt",
        [string]$TextName = "transcript_original.txt",
        [int]$HeartbeatSeconds = 10
    )

    Ensure-Directory $TranscriptFolder
    $resolvedModel = if ([string]::IsNullOrWhiteSpace($Model)) { $script:OpenAiTranscriptionModel } else { $Model.Trim() }
    $chunkPlan = New-OpenAiTranscriptionChunkPlan `
        -AudioPath $AudioPath `
        -FFmpegExe $FFmpegExe `
        -FFprobeExe $FFprobeExe `
        -HeartbeatSeconds $HeartbeatSeconds

    $segments = New-Object System.Collections.Generic.List[object]
    $detectedLanguage = ""
    $segmentId = 0

    try {
        foreach ($chunk in @($chunkPlan.Chunks)) {
            Write-Log ("OpenAI transcription request: {0} (offset {1:0.###}s)" -f (Split-Path -Path $chunk.Path -Leaf), [double]$chunk.StartSeconds)
            $payload = Invoke-OpenAiAudioTranscriptionRequest `
                -AudioPath $chunk.Path `
                -LanguageCode $LanguageCode `
                -Model $resolvedModel

            if ([string]::IsNullOrWhiteSpace($detectedLanguage) -and -not [string]::IsNullOrWhiteSpace([string]$payload.language)) {
                $detectedLanguage = [string]$payload.language
            }

            $payloadSegments = @($payload.segments)
            if ($payloadSegments.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$payload.text)) {
                $payloadSegments = @(
                    [PSCustomObject]@{
                        start = 0.0
                        end   = [double]$chunk.DurationSeconds
                        text  = [string]$payload.text
                    }
                )
            }

            foreach ($segment in $payloadSegments) {
                $text = [string]$segment.text
                if ([string]::IsNullOrWhiteSpace($text)) {
                    continue
                }

                [void]$segments.Add([PSCustomObject]@{
                        id    = $segmentId
                        start = [double]$chunk.StartSeconds + [double]$segment.start
                        end   = [double]$chunk.StartSeconds + [double]$segment.end
                        text  = $text
                    })
                $segmentId += 1
            }
        }

        if ($segments.Count -eq 0) {
            throw "OpenAI transcription completed but returned no transcript segments."
        }

        $artifacts = Write-TranscriptArtifactsFromSegments `
            -OutputFolder $TranscriptFolder `
            -Segments $segments.ToArray() `
            -Language $(if ([string]::IsNullOrWhiteSpace($detectedLanguage)) { $LanguageCode } else { $detectedLanguage }) `
            -SourceLanguage $(if ([string]::IsNullOrWhiteSpace($detectedLanguage)) { $LanguageCode } else { $detectedLanguage }) `
            -Task "transcribe" `
            -JsonName $JsonName `
            -SrtName $SrtName `
            -TextName $TextName

        return [PSCustomObject]@{
            Device   = "openai"
            Fp16     = $false
            JsonPath = $artifacts.JsonPath
            SrtPath  = $artifacts.SrtPath
            TextPath = $artifacts.TextPath
            Language = $(if ([string]::IsNullOrWhiteSpace($detectedLanguage)) { [string]$LanguageCode } else { [string]$detectedLanguage })
            GpuError = ""
        }
    }
    finally {
        if ($chunkPlan -and -not [string]::IsNullOrWhiteSpace($chunkPlan.TempRoot) -and (Test-Path -LiteralPath $chunkPlan.TempRoot)) {
            Remove-Item -LiteralPath $chunkPlan.TempRoot -Recurse -Force -ErrorAction SilentlyContinue
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

    if (Test-Path -LiteralPath $OutputVideo) {
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
        if ($gpuResult.ExitCode -eq 0 -and (Test-Path -LiteralPath $OutputVideo)) {
            return "GPU_NVENC"
        }

        Write-Log "GPU proxy generation failed. Falling back to CPU libx264." "WARN"
        if (Test-Path -LiteralPath $OutputVideo) {
            Remove-Item -LiteralPath $OutputVideo -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Log "Creating proxy video with CPU libx264..."
    $cpuResult = Invoke-ExternalCapture -FilePath $FFmpegExe -Arguments $cpuArgs -StepName "Proxy generation (CPU)" -HeartbeatSeconds $HeartbeatSeconds
    if ($cpuResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $OutputVideo)) {
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

    $existingFrames = @(Get-ChildItem -LiteralPath $FramesFolder -Filter "frame_*.jpg" -ErrorAction SilentlyContinue)
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
        if ($gpuResult.ExitCode -eq 0 -and @(Get-ChildItem -LiteralPath $FramesFolder -Filter "frame_*.jpg" -ErrorAction SilentlyContinue).Count -gt 0) {
            return "GPU_DECODE_ATTEMPT"
        }

        Write-Log "GPU-assisted frame extraction failed. Falling back to CPU." "WARN"
        Get-ChildItem -LiteralPath $FramesFolder -Filter "frame_*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Extracting frames every $FrameIntervalSeconds seconds with CPU path..."
    $cpuResult = Invoke-ExternalCapture -FilePath $FFmpegExe -Arguments $cpuArgs -StepName "Frame extraction (CPU)" -HeartbeatSeconds $HeartbeatSeconds
    if ($cpuResult.ExitCode -ne 0 -or @(Get-ChildItem -LiteralPath $FramesFolder -Filter "frame_*.jpg" -ErrorAction SilentlyContinue).Count -eq 0) {
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

    if (Test-Path -LiteralPath $AudioFile) {
        Write-Log "Audio file already exists. Skipping extraction."
        return "SKIPPED_EXISTING"
    }

    $result = Invoke-ExternalCapture `
        -FilePath $FFmpegExe `
        -Arguments @("-y", "-i", $InputVideo, "-map", "0:a:0", "-vn", "-c:a", "libmp3lame", "-b:a", "192k", $AudioFile) `
        -StepName "Audio extraction" `
        -HeartbeatSeconds $HeartbeatSeconds

    if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $AudioFile)) {
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
    "frame_number,seconds,timestamp,filename,relative_path" | Set-Content -LiteralPath $FrameIndexCsv -Encoding UTF8

    $frames = @(Get-ChildItem -LiteralPath $FramesFolder -Filter "frame_*.jpg" | Sort-Object Name)
    $nextHeartbeat = if ($HeartbeatSeconds -gt 0) { (Get-Date).AddSeconds($HeartbeatSeconds) } else { $null }

    for ($i = 0; $i -lt $frames.Count; $i++) {
        $frame = $frames[$i]
        if ($frame.BaseName -match '^frame_(\d+)$') {
            $frameNumber = [int]$matches[1]
            $seconds = [math]::Round(($frameNumber - 1) * $FrameIntervalSeconds, 3)
            $timestamp = [TimeSpan]::FromSeconds($seconds).ToString("hh\:mm\:ss\.fff")
            $relativePath = "$FramesFolderName/$($frame.Name)"
            "$frameNumber,$seconds,$timestamp,$($frame.Name),$relativePath" | Add-Content -LiteralPath $FrameIndexCsv
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

    if (-not (Test-Path -LiteralPath $VideoPath)) {
        throw "Input video not found: $VideoPath"
    }

    $videoItem = Get-Item -LiteralPath $VideoPath
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
    "==== Script run started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====" | Set-Content -LiteralPath $logFile -Encoding UTF8

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
            if (-not (Test-Path -LiteralPath $rawVideoPath)) {
                Write-Log "Copying raw video..."
                Copy-Item -LiteralPath $videoItem.FullName -Destination $rawVideoPath -Force
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
            if ((Test-Path -LiteralPath $transcriptSrt) -and (Test-Path -LiteralPath $transcriptJson)) {
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

                if (-not (Test-Path -LiteralPath $transcriptSrt)) {
                    throw "Expected SRT not found: $transcriptSrt"
                }

                if (-not (Test-Path -LiteralPath $transcriptJson)) {
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

$appVersion = Get-AppVersion

if ($Version) {
    Write-Host ("{0} v{1}" -f $script:AppName, $appVersion) -ForegroundColor Cyan
    return
}

Write-Host ("{0} v{1}" -f $script:AppName, $appVersion) -ForegroundColor Cyan
Write-Phase -Name "Preflight" -Detail "Resolving tools and inputs"

$FFmpegPath = Resolve-ExecutablePath `
    -PreferredPath $FFmpegPath `
    -FallbackCommands @("ffmpeg") `
    -FallbackPaths @("D:\APPS\ffmpeg\bin\ffmpeg.exe", "C:\APPS\ffmpeg\bin\ffmpeg.exe", "C:\Program Files\digiKam\ffmpeg.exe") `
    -ToolName "FFmpeg"
$FFprobePath = Get-FFprobePath -FFmpegExe $FFmpegPath
$PythonExe = Resolve-ExecutablePath `
    -PreferredPath $PythonExe `
    -FallbackCommands @("py", "python") `
    -FallbackPaths @() `
    -ToolName "Python launcher"

$resolvedDefaults = Resolve-DefaultInputOutputFolders `
    -CurrentInputFolder $InputFolder `
    -CurrentOutputFolder $OutputFolder `
    -InputProvided:$($PSBoundParameters.ContainsKey("InputFolder")) `
    -OutputProvided:$($PSBoundParameters.ContainsKey("OutputFolder")) `
    -NoPrompt:$NoPrompt
$InputFolder = $resolvedDefaults.InputFolder
$OutputFolder = $resolvedDefaults.OutputFolder

$requestedInputValue = $InputPath
if (-not $PSBoundParameters.ContainsKey("InputPath") -and -not $NoPrompt) {
    $requestedInputValue = Get-InteractiveInputSource `
        -DefaultInputFolder $InputFolder `
        -YtDlpCommand $YtDlpPath `
        -PythonCommand $PythonExe
}

$remoteInputSources = @()
$InputPath = $null

if ($null -ne $requestedInputValue) {
    if ($requestedInputValue -is [System.Array]) {
        $remoteInputSources = @($requestedInputValue)
    }
    elseif (Test-IsHttpUrl -Value $requestedInputValue) {
        $remoteInputSources = @([string]$requestedInputValue)
    }
    else {
        $detectedRemoteUrls = @(Get-HttpUrlsFromText -Value ([string]$requestedInputValue))
        if ($detectedRemoteUrls.Count -gt 1) {
            $remoteInputSources = $detectedRemoteUrls
        }
        else {
            $InputPath = [string]$requestedInputValue
        }
    }
}

function Get-TranslationTargets {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value -split '[,\s]+' |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

function Convert-ToSrtTimestamp {
    param([double]$Seconds)

    $totalMs = [int][math]::Round($Seconds * 1000)
    $hours = [math]::Floor($totalMs / 3600000)
    $totalMs = $totalMs % 3600000
    $minutes = [math]::Floor($totalMs / 60000)
    $totalMs = $totalMs % 60000
    $secondsPart = [math]::Floor($totalMs / 1000)
    $millis = $totalMs % 1000
    return ("{0:00}:{1:00}:{2:00},{3:000}" -f $hours, $minutes, $secondsPart, $millis)
}

function Write-TranscriptArtifactsFromSegments {
    param(
        [string]$OutputFolder,
        [array]$Segments,
        [string]$Language,
        [string]$JsonName,
        [string]$SrtName,
        [string]$TextName,
        [string]$Task = "translate",
        [string]$SourceLanguage = ""
    )

    Ensure-Directory $OutputFolder

    $jsonPath = Join-Path $OutputFolder $JsonName
    $srtPath = Join-Path $OutputFolder $SrtName
    $textPath = Join-Path $OutputFolder $TextName

    $jsonPayload = [PSCustomObject]@{
        language        = $Language
        source_language = $SourceLanguage
        task            = $Task
        text            = (($Segments | ForEach-Object { $_.text }) -join " ").Trim()
        segments        = @(
            $Segments | ForEach-Object {
                [PSCustomObject]@{
                    id    = $_.id
                    start = $_.start
                    end   = $_.end
                    text  = $_.text
                }
            }
        )
    }

    $jsonPayload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $srtBuilder = New-Object System.Text.StringBuilder
    $textBuilder = New-Object System.Text.StringBuilder
    $index = 1
    foreach ($segment in $Segments) {
        $text = [string]$segment.text
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        [void]$srtBuilder.AppendLine($index)
        [void]$srtBuilder.AppendLine(("{0} --> {1}" -f (Convert-ToSrtTimestamp -Seconds $segment.start), (Convert-ToSrtTimestamp -Seconds $segment.end)))
        [void]$srtBuilder.AppendLine($text.Trim())
        [void]$srtBuilder.AppendLine("")
        [void]$textBuilder.AppendLine($text.Trim())
        $index += 1
    }

    $srtBuilder.ToString() | Set-Content -LiteralPath $srtPath -Encoding UTF8
    $textBuilder.ToString() | Set-Content -LiteralPath $textPath -Encoding UTF8

    return [PSCustomObject]@{
        JsonPath = $jsonPath
        SrtPath  = $srtPath
        TextPath = $textPath
    }
}

function Get-InteractiveTranslationProvider {
    param(
        [string]$DefaultValue = "Auto",
        [ref]$WasExplicitSelection = $null
    )

    while ($true) {
        Write-Host ""
        Write-Host "Translation provider" -ForegroundColor Cyan
        Write-Host "Media Manglers always works from the original spoken source first." -ForegroundColor Cyan
        Write-Host "Auto chooses the best available path for each requested language." -ForegroundColor Cyan
        Write-Host "  1. Auto   best available per target (default)" -ForegroundColor Cyan
        Write-Host "  2. OpenAI best quality, needs a configured OpenAI API key" -ForegroundColor Cyan
        Write-Host "  3. Local  free fallback using local tools on this PC" -ForegroundColor Cyan

        $choice = Read-Host "Press Enter for Auto, or type 1, 2, or 3"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            if ($WasExplicitSelection) {
                $WasExplicitSelection.Value = $false
            }
            return $DefaultValue
        }

        switch ($choice.Trim()) {
            "1" {
                if ($WasExplicitSelection) {
                    $WasExplicitSelection.Value = $true
                }
                return "Auto"
            }
            "2" {
                if ($WasExplicitSelection) {
                    $WasExplicitSelection.Value = $true
                }
                return "OpenAI"
            }
            "3" {
                if ($WasExplicitSelection) {
                    $WasExplicitSelection.Value = $true
                }
                return "Local"
            }
            default {
                Write-Host "Please enter 1, 2, 3, or just press Enter for Auto." -ForegroundColor Yellow
            }
        }
    }
}

function Get-InteractiveProcessingMode {
    param([string]$DefaultValue = "Local")

    while ($true) {
        Write-Host ""
        Write-Host "Processing mode" -ForegroundColor Cyan
        Write-Host "Choose the full workflow you want Audio Mangler to use." -ForegroundColor Cyan
        Write-Host "  1. Local   transcription and translation stay on this PC" -ForegroundColor Cyan
        Write-Host "  2. AI      uses OpenAI where the selected AI project mode allows it" -ForegroundColor Cyan

        $choice = Read-Host "Press Enter for Local, or type 1 or 2"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return $DefaultValue
        }

        switch ($choice.Trim()) {
            "1" { return "Local" }
            "2" { return "AI" }
            default { Write-Host "Please enter 1, 2, or just press Enter for Local." -ForegroundColor Yellow }
        }
    }
}

function Get-InteractiveOpenAiProjectMode {
    param([string]$DefaultValue = "Private")

    while ($true) {
        Write-Host ""
        Write-Host "AI project mode" -ForegroundColor Cyan
        Write-Host "  1. Private  OpenAI transcription + OpenAI translation (default)" -ForegroundColor Cyan
        Write-Host "  2. Public   local transcription + OpenAI translation on the shared project" -ForegroundColor Cyan

        $choice = Read-Host "Press Enter for Private, or type 1 or 2"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return $DefaultValue
        }

        switch ($choice.Trim()) {
            "1" { return "Private" }
            "2" { return "Public" }
            default { Write-Host "Please enter 1, 2, or just press Enter for Private." -ForegroundColor Yellow }
        }
    }
}

function Get-ProcessingModeSummary {
    param(
        [string]$EffectiveMode,
        [string]$ProjectMode
    )

    if ($EffectiveMode -ne "AI") {
        return "Local"
    }

    if ($ProjectMode -eq "Public") {
        return "AI Public"
    }

    return "AI Private"
}

function Get-TranscriptionProviderDetails {
    param(
        [string]$EffectiveMode,
        [string]$ProjectMode,
        [string]$Model = ""
    )

    if ($EffectiveMode -ne "AI") {
        return "Local (Whisper transcription)"
    }

    if ($ProjectMode -eq "Public") {
        return "Local (Whisper transcription, AI Public keeps audio on this PC)"
    }

    $resolvedModel = if ([string]::IsNullOrWhiteSpace($Model)) {
        $script:OpenAiTranscriptionModel
    }
    else {
        $Model.Trim()
    }

    return ("OpenAI ({0} transcription)" -f $resolvedModel)
}

function Get-TranslationModeSummary {
    param(
        [string]$EffectiveMode,
        [string]$ProjectMode,
        [string]$Model,
        [bool]$TranslationRequested = $true
    )

    if (-not $TranslationRequested) {
        return "not requested"
    }

    if ($EffectiveMode -eq "AI") {
        $projectLabel = if ([string]::IsNullOrWhiteSpace($ProjectMode)) { "Private" } else { $ProjectMode }
        if ([string]::IsNullOrWhiteSpace($Model)) {
            return ("OpenAI translation ({0} project)" -f $projectLabel)
        }

        return ("OpenAI translation via {0} ({1} project)" -f $Model, $projectLabel)
    }

    return "Local translation on this PC"
}

function Get-TranslationModeForProcessingMode {
    param([string]$EffectiveMode)

    if ($EffectiveMode -eq "AI") {
        return "OpenAI"
    }

    return "Local"
}

function Resolve-ProcessingModeRequest {
    param(
        [string]$RequestedMode = "",
        [switch]$WasExplicitlySet,
        [string]$RequestedLegacyTranslationProvider = "",
        [switch]$LegacyProviderWasExplicitlySet,
        [switch]$InteractiveMode
    )

    $requestedModeValue = if ([string]::IsNullOrWhiteSpace($RequestedMode)) {
        ""
    }
    else {
        $RequestedMode.Trim()
    }

    $legacyProviderValue = if ([string]::IsNullOrWhiteSpace($RequestedLegacyTranslationProvider)) {
        ""
    }
    else {
        $RequestedLegacyTranslationProvider.Trim()
    }

    $selectionSource = "default"
    $effectiveMode = $requestedModeValue
    $resolutionNotes = New-Object System.Collections.Generic.List[string]

    if ($WasExplicitlySet) {
        $selectionSource = "explicit"
        if ([string]::IsNullOrWhiteSpace($effectiveMode)) {
            $effectiveMode = "Local"
        }

        if ($LegacyProviderWasExplicitlySet) {
            $legacyMappedMode = switch ($legacyProviderValue) {
                "Local"  { "Local" }
                "OpenAI" { "AI" }
                "Auto"   { if (Test-OpenAiTranslationAvailable) { "AI" } else { "Local" } }
                default  { "" }
            }

            if (-not [string]::IsNullOrWhiteSpace($legacyMappedMode) -and $legacyMappedMode -ne $effectiveMode) {
                [void]$resolutionNotes.Add(("ProcessingMode {0} overrides legacy TranslationProvider {1}." -f $effectiveMode, $legacyProviderValue))
            }
        }
    }
    elseif ($LegacyProviderWasExplicitlySet) {
        $selectionSource = "legacy TranslationProvider"
        switch ($legacyProviderValue) {
            "Local" {
                $effectiveMode = "Local"
                [void]$resolutionNotes.Add("Legacy TranslationProvider Local maps to ProcessingMode Local.")
            }
            "OpenAI" {
                $effectiveMode = "AI"
                [void]$resolutionNotes.Add("Legacy TranslationProvider OpenAI maps to ProcessingMode AI.")
            }
            "Auto" {
                if (Test-OpenAiTranslationAvailable) {
                    $effectiveMode = "AI"
                    [void]$resolutionNotes.Add("Legacy TranslationProvider Auto mapped to ProcessingMode AI because an OpenAI key is available.")
                }
                else {
                    $effectiveMode = "Local"
                    [void]$resolutionNotes.Add("Legacy TranslationProvider Auto mapped to ProcessingMode Local because no OpenAI key is available.")
                }
            }
            default {
                $effectiveMode = "Local"
                [void]$resolutionNotes.Add(("Unknown legacy TranslationProvider value '{0}' was treated as Local." -f $legacyProviderValue))
            }
        }
    }
    elseif ($InteractiveMode) {
        $effectiveMode = Get-InteractiveProcessingMode -DefaultValue "Local"
        $selectionSource = "interactive"
    }
    else {
        $effectiveMode = "Local"
        [void]$resolutionNotes.Add("Processing mode defaulted to Local because no explicit mode was provided.")
    }

    return [PSCustomObject]@{
        RequestedMode        = $requestedModeValue
        EffectiveMode        = $effectiveMode
        SelectionSource      = $selectionSource
        ResolutionNote       = ($resolutionNotes -join " ")
        RequestedLegacyValue = $legacyProviderValue
    }
}

function Test-OpenAiDiagnosticsEnabled {
    $diagnosticsSetting = [Environment]::GetEnvironmentVariable("MM_OPENAI_DIAGNOSTICS")
    if ([string]::IsNullOrWhiteSpace($diagnosticsSetting)) {
        return $false
    }

    return $diagnosticsSetting.Trim() -notmatch '^(?i)(0|false|no|off)$'
}

function Normalize-OpenAiModelId {
    param([string]$ModelId)

    if ([string]::IsNullOrWhiteSpace($ModelId)) {
        return ""
    }

    return $ModelId.Trim().ToLowerInvariant()
}

function Get-OpenAiApprovedTranslationModels {
    param([string]$ProjectMode)

    if ($ProjectMode -eq "Public") {
        return @($script:OpenAiPublicTranslationApprovedModels)
    }

    return @($script:OpenAiPrivateTranslationApprovedModels)
}

function Get-OpenAiApprovedTranscriptionModels {
    param([string]$ProjectMode)

    if ($ProjectMode -eq "Public") {
        return @()
    }

    return @($script:OpenAiPrivateTranscriptionApprovedModels)
}

function Get-OpenAiApprovedModelFallbackDefault {
    param(
        [ValidateSet("Translation", "Transcription")]
        [string]$Capability,
        [string]$ProjectMode
    )

    if ($Capability -eq "Translation") {
        if ($ProjectMode -eq "Public") {
            return $script:OpenAiPublicTranslationDefaultModel
        }

        return $script:OpenAiPrivateTranslationDefaultModel
    }

    return $script:OpenAiTranscriptionModel
}

function Resolve-OpenAiApprovedModelName {
    param(
        [string]$RequestedModel,
        [string[]]$ApprovedModels
    )

    $normalizedRequestedModel = Normalize-OpenAiModelId -ModelId $RequestedModel
    if ([string]::IsNullOrWhiteSpace($normalizedRequestedModel)) {
        return $null
    }

    foreach ($approvedModel in @($ApprovedModels)) {
        if ((Normalize-OpenAiModelId -ModelId $approvedModel) -eq $normalizedRequestedModel) {
            return $approvedModel
        }
    }

    return $null
}

function Get-OpenAiApprovedAccessibleModels {
    param(
        [string[]]$ApprovedModels,
        [string[]]$AccessibleModels
    )

    $accessibleLookup = @{}
    foreach ($modelId in @($AccessibleModels)) {
        $normalizedModelId = Normalize-OpenAiModelId -ModelId $modelId
        if (-not [string]::IsNullOrWhiteSpace($normalizedModelId)) {
            $accessibleLookup[$normalizedModelId] = $true
        }
    }

    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($approvedModel in @($ApprovedModels)) {
        $normalizedApprovedModel = Normalize-OpenAiModelId -ModelId $approvedModel
        if ($accessibleLookup.ContainsKey($normalizedApprovedModel)) {
            [void]$matches.Add($approvedModel)
        }
    }

    return $matches.ToArray()
}

function Test-OpenAiModelDiscoveryFallbackAllowed {
    param([PSCustomObject]$DiscoveryResult)

    if ($null -eq $DiscoveryResult) {
        return $false
    }

    if ($DiscoveryResult.Success) {
        return $false
    }

    if ($DiscoveryResult.Skipped) {
        return $true
    }

    $failureCategory = ""
    if ($DiscoveryResult.FailureDetails) {
        $failureCategory = [string]$DiscoveryResult.FailureDetails.Category
    }

    return $failureCategory -in @("", "Network", "Timeout", "ServerError", "Unexpected")
}

function Get-OpenAiAccessibleModelIds {
    param(
        [string]$ProjectMode,
        [string]$ProviderLabel = "OpenAI model discovery"
    )

    $resolvedProjectMode = if ([string]::IsNullOrWhiteSpace($ProjectMode)) {
        "Private"
    }
    else {
        $ProjectMode.Trim()
    }

    $cacheKey = $resolvedProjectMode.ToLowerInvariant()
    if ($script:OpenAiModelDiscoveryCache.ContainsKey($cacheKey)) {
        return $script:OpenAiModelDiscoveryCache[$cacheKey]
    }

    $testMode = Get-OpenAiTestMode
    if (-not [string]::IsNullOrWhiteSpace($testMode)) {
        $result = [PSCustomObject]@{
            Success        = $false
            Skipped        = $true
            ModelIds       = @()
            Endpoint       = "https://api.openai.com/v1/models"
            ErrorMessage   = ("OpenAI model discovery was skipped because MM_TEST_OPENAI_MODE='{0}' is active." -f $testMode)
            NextStep       = ""
            FailureDetails = $null
        }
        $script:OpenAiModelDiscoveryCache[$cacheKey] = $result
        return $result
    }

    $apiKey = Get-OpenAiApiKey -Required -ProviderLabel $ProviderLabel
    $endpoint = "https://api.openai.com/v1/models"

    try {
        $response = Invoke-RestMethod -Method Get -Uri $endpoint -Headers @{ Authorization = "Bearer $apiKey" }
        $modelIds = @(
            $response.data |
                ForEach-Object { [string]$_.id } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )

        $result = [PSCustomObject]@{
            Success        = $true
            Skipped        = $false
            ModelIds       = @($modelIds)
            Endpoint       = $endpoint
            ErrorMessage   = ""
            NextStep       = ""
            FailureDetails = $null
        }
    }
    catch {
        $failureDetails = Get-OpenAiFailureDetails -Exception $_.Exception
        $errorMessage = if ($failureDetails -and -not [string]::IsNullOrWhiteSpace($failureDetails.UserMessage)) {
            $failureDetails.UserMessage
        }
        else {
            ("OpenAI model discovery failed: {0}" -f $_.Exception.Message)
        }

        $nextStep = if ($failureDetails -and -not [string]::IsNullOrWhiteSpace($failureDetails.NextStep)) {
            $failureDetails.NextStep
        }
        else {
            "Check the OpenAI project permissions and network access, then try again."
        }

        $result = [PSCustomObject]@{
            Success        = $false
            Skipped        = $false
            ModelIds       = @()
            Endpoint       = $endpoint
            ErrorMessage   = $errorMessage
            NextStep       = $nextStep
            FailureDetails = $failureDetails
        }
    }

    $script:OpenAiModelDiscoveryCache[$cacheKey] = $result
    return $result
}

function Resolve-OpenAiApprovedModelSelection {
    param(
        [ValidateSet("Translation", "Transcription")]
        [string]$Capability,
        [string]$ProjectMode,
        [string]$RequestedModel = "",
        [switch]$WasExplicitlySet
    )

    $resolvedProjectMode = if ([string]::IsNullOrWhiteSpace($ProjectMode)) {
        "Private"
    }
    else {
        $ProjectMode.Trim()
    }

    $approvedModels = if ($Capability -eq "Translation") {
        Get-OpenAiApprovedTranslationModels -ProjectMode $resolvedProjectMode
    }
    else {
        Get-OpenAiApprovedTranscriptionModels -ProjectMode $resolvedProjectMode
    }

    if (@($approvedModels).Count -eq 0) {
        throw ("OpenAI {0} model selection is not available for AI {1}." -f $Capability.ToLowerInvariant(), $resolvedProjectMode)
    }

    $defaultModel = Get-OpenAiApprovedModelFallbackDefault -Capability $Capability -ProjectMode $resolvedProjectMode
    $requestedApprovedModel = $null
    if ($WasExplicitlySet -and -not [string]::IsNullOrWhiteSpace($RequestedModel)) {
        $requestedApprovedModel = Resolve-OpenAiApprovedModelName -RequestedModel $RequestedModel -ApprovedModels $approvedModels
        if ([string]::IsNullOrWhiteSpace($requestedApprovedModel)) {
            throw ("OpenAI {0} model '{1}' is not allowed for AI {2}. Approved models: {3}" -f $Capability.ToLowerInvariant(), $RequestedModel.Trim(), $resolvedProjectMode, ($approvedModels -join ", "))
        }
    }

    $providerLabel = if ($Capability -eq "Translation") { "OpenAI translation" } else { "OpenAI transcription" }
    $discoveryResult = Get-OpenAiAccessibleModelIds -ProjectMode $resolvedProjectMode -ProviderLabel $providerLabel
    if ($discoveryResult.Success) {
        $accessibleApprovedModels = @(Get-OpenAiApprovedAccessibleModels -ApprovedModels $approvedModels -AccessibleModels $discoveryResult.ModelIds)

        if (Test-OpenAiDiagnosticsEnabled) {
            Write-Log ("OpenAI {0} model discovery for AI {1}: approved visible models = {2}" -f $Capability.ToLowerInvariant(), $resolvedProjectMode, $(if ($accessibleApprovedModels.Count -gt 0) { $accessibleApprovedModels -join ", " } else { "none" }))
        }

        if ($requestedApprovedModel) {
            if ($accessibleApprovedModels -contains $requestedApprovedModel) {
                return [PSCustomObject]@{
                    ResolvedModel            = $requestedApprovedModel
                    SelectionSource          = "explicit"
                    ResolutionNote           = ("OpenAI {0} model '{1}' was explicitly requested and confirmed for AI {2}." -f $Capability.ToLowerInvariant(), $requestedApprovedModel, $resolvedProjectMode)
                    ApprovedModels           = @($approvedModels)
                    AccessibleApprovedModels = @($accessibleApprovedModels)
                    DiscoveryStatus          = "success"
                }
            }

            throw ("OpenAI {0} model '{1}' is approved for AI {2}, but this API key/project cannot access it. Approved models visible to this key: {3}. Expected approved models: {4}" -f $Capability.ToLowerInvariant(), $requestedApprovedModel, $resolvedProjectMode, $(if ($accessibleApprovedModels.Count -gt 0) { $accessibleApprovedModels -join ", " } else { "none" }), ($approvedModels -join ", "))
        }

        if ($accessibleApprovedModels.Count -gt 0) {
            return [PSCustomObject]@{
                ResolvedModel            = $accessibleApprovedModels[0]
                SelectionSource          = "detected"
                ResolutionNote           = ("OpenAI {0} model auto-detected from the approved AI {1} allowlist: {2}" -f $Capability.ToLowerInvariant(), $resolvedProjectMode, $accessibleApprovedModels[0])
                ApprovedModels           = @($approvedModels)
                AccessibleApprovedModels = @($accessibleApprovedModels)
                DiscoveryStatus          = "success"
            }
        }

        throw ("OpenAI {0} cannot continue because AI {1} does not have access to any approved models. Expected one of: {2}" -f $Capability.ToLowerInvariant(), $resolvedProjectMode, ($approvedModels -join ", "))
    }

    if (-not (Test-OpenAiModelDiscoveryFallbackAllowed -DiscoveryResult $discoveryResult)) {
        $errorSuffix = if (-not [string]::IsNullOrWhiteSpace($discoveryResult.NextStep)) {
            (" {0}" -f $discoveryResult.NextStep)
        }
        else {
            ""
        }

        throw ("OpenAI {0} model discovery failed before a safe approved model could be confirmed for AI {1}. {2}{3}" -f $Capability.ToLowerInvariant(), $resolvedProjectMode, $discoveryResult.ErrorMessage, $errorSuffix)
    }

    if ($requestedApprovedModel) {
        return [PSCustomObject]@{
            ResolvedModel            = $requestedApprovedModel
            SelectionSource          = "explicit"
            ResolutionNote           = ("OpenAI {0} model discovery could not confirm visibility. Using the approved explicit model '{1}' for AI {2}. {3}" -f $Capability.ToLowerInvariant(), $requestedApprovedModel, $resolvedProjectMode, $discoveryResult.ErrorMessage)
            ApprovedModels           = @($approvedModels)
            AccessibleApprovedModels = @()
            DiscoveryStatus          = "fallback"
        }
    }

    $fallbackModel = $defaultModel
    if ([string]::IsNullOrWhiteSpace((Resolve-OpenAiApprovedModelName -RequestedModel $fallbackModel -ApprovedModels $approvedModels))) {
        $fallbackModel = @($approvedModels)[0]
    }

    return [PSCustomObject]@{
        ResolvedModel            = $fallbackModel
        SelectionSource          = "fallback-default"
        ResolutionNote           = ("OpenAI {0} model discovery could not confirm visibility. Falling back to the approved default '{1}' for AI {2}. {3}" -f $Capability.ToLowerInvariant(), $fallbackModel, $resolvedProjectMode, $discoveryResult.ErrorMessage)
        ApprovedModels           = @($approvedModels)
        AccessibleApprovedModels = @()
        DiscoveryStatus          = "fallback"
    }
}

function Get-OpenAiKeyPreference {
    $projectMode = if ([string]::IsNullOrWhiteSpace($OpenAiProject)) {
        "Private"
    }
    else {
        $OpenAiProject.Trim()
    }

    $primaryVariable = if ($projectMode -eq "Public") {
        "OPENAI_API_KEY_PUBLIC"
    }
    else {
        "OPENAI_API_KEY_PRIVATE"
    }

    return [PSCustomObject]@{
        ProjectMode         = $projectMode
        PrimaryVariable     = $primaryVariable
        LegacyVariable      = "OPENAI_API_KEY"
        AllowLegacyFallback = ($projectMode -eq "Private")
    }
}

function Find-EnvironmentVariableValue {
    param([string]$Name)

    foreach ($scope in @(
            [System.EnvironmentVariableTarget]::Process,
            [System.EnvironmentVariableTarget]::User,
            [System.EnvironmentVariableTarget]::Machine)) {
        $candidate = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return [string]$candidate
        }
    }

    return $null
}

function Get-OpenAiProjectModeSummary {
    $keyPreference = Get-OpenAiKeyPreference
    if ($keyPreference.ProjectMode -eq "Public") {
        return "Public (explicit)"
    }

    return "Private (default)"
}

function Get-OpenAiKeyRequirementText {
    param([string]$ProviderLabel = "OpenAI translation")

    $keyPreference = Get-OpenAiKeyPreference
    if ($keyPreference.AllowLegacyFallback) {
        return ("{0} cannot continue until {1} is set, or legacy {2} is available." -f $ProviderLabel, $keyPreference.PrimaryVariable, $keyPreference.LegacyVariable)
    }

    return ("{0} cannot continue until {1} is set. Public mode requires an explicit Public project key." -f $ProviderLabel, $keyPreference.PrimaryVariable)
}

function Get-OpenAiKeyTroubleshootingText {
    return "Check the selected OpenAI API key, make sure it belongs to the intended OpenAI Platform project, and turn on Request permission for Chat Completions."
}

function Get-OpenAiSetupInstructionLines {
    param(
        [string]$ProviderLabel = "OpenAI translation",
        [ValidateSet("Interactive", "NonInteractive")]
        [string]$Audience = "NonInteractive"
    )

    $keyPreference = Get-OpenAiKeyPreference
    $lines = @(
        ("{0} was selected, but no API key is available." -f $ProviderLabel),
        "",
        ("Current key profile: {0}" -f (Get-OpenAiProjectModeSummary)),
        ("Preferred environment variable: {0}" -f $keyPreference.PrimaryVariable),
        "",
        ("To use {0}, create a key in your OpenAI Platform account:" -f $ProviderLabel),
        "https://platform.openai.com/api-keys",
        "",
        "Recommended setup for normal use:",
        "- Owned by you",
        "- Dedicated project",
        "- Restricted",
        "- Turn on Request for Chat Completions (/v1/chat/completions)",
        "- Leave unrelated permissions off or set them to None",
        "- Read Only will not work",
        "",
        "Service accounts are mainly for shared or server automation, not normal personal desktop use.",
        "ChatGPT subscriptions and OpenAI API billing are separate.",
        ("If API billing or credits are missing, {0} will not run." -f $ProviderLabel.ToLowerInvariant()),
        "OpenAI API usage may cost money.",
        "If you are unsure, use Private."
    )

    if ($keyPreference.ProjectMode -eq "Public") {
        $lines += "Public mode only works when you explicitly choose -OpenAiProject Public."
        $lines += "The script cannot infer a key's sharing behavior from the secret value."
    }
    else {
        $lines += "Private is the default and safest mode."
        $lines += ("Legacy fallback is still supported for older setups: {0}" -f $keyPreference.LegacyVariable)
    }

    $lines += ""
    $lines += "Use it now:"
    $lines += ('  $env:{0}="sk-..."' -f $keyPreference.PrimaryVariable)
    $lines += "Save it for later:"
    $lines += ('  [System.Environment]::SetEnvironmentVariable("{0}","sk-...","User")' -f $keyPreference.PrimaryVariable)

    if ($Audience -eq "Interactive") {
        $lines += "If you save it for later, open a new PowerShell window before re-checking."
    }
    else {
        if ($keyPreference.ProjectMode -eq "Public") {
            $lines += "Then open a new PowerShell window and rerun with -ProcessingMode AI -OpenAiProject Public."
        }
        else {
            $lines += "Then open a new PowerShell window and rerun with -ProcessingMode AI -OpenAiProject Private."
        }
        $lines += "Do not hardcode the key or commit it to GitHub."
        $lines += "If you do not want OpenAI, rerun with -ProcessingMode Local."
    }

    return $lines
}

function Get-OpenAiSetupInstructionsText {
    param(
        [string]$ProviderLabel = "OpenAI translation"
    )

    return ((Get-OpenAiSetupInstructionLines -ProviderLabel $ProviderLabel -Audience "NonInteractive") -join "`n")
}

function Show-OpenAiSetupGuidance {
    param(
        [string]$ProviderLabel = "OpenAI translation"
    )

    Write-Host ""
    foreach ($line in (Get-OpenAiSetupInstructionLines -ProviderLabel $ProviderLabel -Audience "NonInteractive")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            Write-Host ""
            continue
        }

        if ($line.StartsWith("  ")) {
            Write-Host $line -ForegroundColor DarkYellow
            continue
        }

        Write-Host $line -ForegroundColor Yellow
    }
}

function Read-OpenAiApiKeyForCurrentRun {
    if ([System.Console]::IsInputRedirected) {
        $rawValue = Read-Host "Paste the OpenAI API key for this run only"
        return [string]$rawValue
    }

    $secureValue = Read-Host "Paste the OpenAI API key for this run only" -AsSecureString
    if ($null -eq $secureValue) {
        return ""
    }

    return [pscredential]::new("openai", $secureValue).GetNetworkCredential().Password
}

function Get-InteractiveOpenAiRecoveryDecision {
    $showSetupGuidance = $true
    while ($true) {
        Write-Host ""
        if ($showSetupGuidance) {
            foreach ($line in (Get-OpenAiSetupInstructionLines -ProviderLabel "OpenAI translation" -Audience "Interactive")) {
                if ([string]::IsNullOrWhiteSpace($line)) {
                    Write-Host ""
                    continue
                }

                if ($line.StartsWith("  ")) {
                    Write-Host $line -ForegroundColor DarkYellow
                    continue
                }

                Write-Host $line -ForegroundColor Yellow
            }
            $showSetupGuidance = $false
        }
        Write-Host "Choose how to continue:" -ForegroundColor Yellow
        Write-Host "  1. Paste API key for this run only" -ForegroundColor Cyan
        Write-Host "  2. Re-check after setting the OpenAI API key externally" -ForegroundColor Cyan
        Write-Host "  3. Switch to Auto" -ForegroundColor Cyan
        Write-Host "  4. Switch to Local" -ForegroundColor Cyan
        Write-Host "  5. Cancel" -ForegroundColor Cyan

        $choice = Read-Host "Type 1, 2, 3, 4, or 5"
        switch ($choice.Trim()) {
            "1" {
                $pastedKey = [string](Read-OpenAiApiKeyForCurrentRun)
                if ([string]::IsNullOrWhiteSpace($pastedKey)) {
                    Write-Host "No API key was pasted. Try again or choose a different option." -ForegroundColor Yellow
                    continue
                }

                $script:SessionOpenAiApiKey = $pastedKey.Trim()
                return [PSCustomObject]@{
                    EffectiveProvider = "OpenAI"
                    ResolutionNote    = "OpenAI translation was selected. Using an API key pasted for this run only."
                }
            }
            "2" {
                if (Test-OpenAiTranslationAvailable) {
                    return [PSCustomObject]@{
                        EffectiveProvider = "OpenAI"
                        ResolutionNote    = "OpenAI translation was selected. An OpenAI API key was found after re-check."
                    }
                }

                Write-Host "An OpenAI API key still is not set. Set it in another window, then re-check, or choose a different option." -ForegroundColor Yellow
            }
            "3" {
                return [PSCustomObject]@{
                    EffectiveProvider = "Auto"
                    ResolutionNote    = "OpenAI translation was selected, but the OpenAI API key is missing. Interactive recovery selected: Auto."
                }
            }
            "4" {
                return [PSCustomObject]@{
                    EffectiveProvider = "Local"
                    ResolutionNote    = "OpenAI translation was selected, but the OpenAI API key is missing. Interactive recovery selected: Local."
                }
            }
            "5" {
                throw (Get-OpenAiKeyRequirementText)
            }
            default {
                Write-Host "Please type 1, 2, 3, 4, or 5." -ForegroundColor Yellow
            }
        }
    }
}

function Get-OpenAiTestMode {
    $rawMode = [string][Environment]::GetEnvironmentVariable("MM_TEST_OPENAI_MODE", [System.EnvironmentVariableTarget]::Process)
    if ([string]::IsNullOrWhiteSpace($rawMode)) {
        return ""
    }

    $normalized = $rawMode.Trim().ToLowerInvariant().Replace("-", "_").Replace(" ", "_")
    switch ($normalized) {
        "success"              { return "success" }
        "401"                  { return "unauthorized" }
        "unauthorized"         { return "unauthorized" }
        "invalid_key"          { return "unauthorized" }
        "403"                  { return "permission_denied" }
        "permission"           { return "permission_denied" }
        "permission_denied"    { return "permission_denied" }
        "429"                  { return "rate_limit" }
        "rate_limit"           { return "rate_limit" }
        "rate_limit_exceeded"  { return "rate_limit" }
        "quota"                { return "quota" }
        "billing"              { return "quota" }
        "credits"              { return "quota" }
        "no_credits"           { return "quota" }
        "insufficient_quota"   { return "quota" }
        "500"                  { return "server_error" }
        "server_error"         { return "server_error" }
        "timeout"              { return "timeout" }
        "network"              { return "network" }
        default {
            throw "Unsupported MM_TEST_OPENAI_MODE value '$rawMode'. Use success, unauthorized, permission_denied, rate_limit, quota, server_error, timeout, or network."
        }
    }
}

function Get-OpenAiQuotaUserMessage {
    return "OpenAI rejected this request because API billing or credits are not available for this project or account. ChatGPT subscriptions and API billing are separate. Add payment details / credits in the OpenAI API billing settings, wait a few minutes, then try again."
}

function Get-OpenAiQuotaNextStep {
    return "After API billing is active, retry the translation, or rerun with -ProcessingMode Local to keep everything on this PC."
}

function Get-OpenAiFailureCategoryLabel {
    param([string]$Category)

    switch ($Category) {
        "Quota"            { return "quota/billing" }
        "RateLimit"        { return "rate limit" }
        "Unauthorized"     { return "unauthorized/bad key" }
        "PermissionDenied" { return "permission denied" }
        "Timeout"          { return "timeout" }
        "Network"          { return "network" }
        "ServerError"      { return "server error" }
        default            { return "unknown" }
    }
}

function Get-OpenAiHeaderValue {
    param(
        $Headers,
        [string[]]$Names
    )

    if ($null -eq $Headers -or $null -eq $Names) {
        return ""
    }

    foreach ($name in $Names) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        try {
            $values = $null
            if ($Headers.TryGetValues($name, [ref]$values)) {
                $joined = @($values) -join ", "
                if (-not [string]::IsNullOrWhiteSpace($joined)) {
                    return $joined
                }
            }
        }
        catch {
        }

        try {
            $value = $Headers[$name]
            if ($null -ne $value) {
                $joined = if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    @($value) -join ", "
                }
                else {
                    [string]$value
                }

                if (-not [string]::IsNullOrWhiteSpace($joined)) {
                    return $joined
                }
            }
        }
        catch {
        }

        try {
            $values = $Headers.GetValues($name)
            if ($values) {
                $joined = @($values) -join ", "
                if (-not [string]::IsNullOrWhiteSpace($joined)) {
                    return $joined
                }
            }
        }
        catch {
        }
    }

    return ""
}

function Normalize-OpenAiResponseText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $trimmed = $Text.Trim()
    try {
        return (($trimmed | ConvertFrom-Json) | ConvertTo-Json -Depth 20 -Compress)
    }
    catch {
        return (($trimmed -replace "\r\n", " ") -replace "\n", " ").Trim()
    }
}

function Get-OpenAiErrorResponseText {
    param([System.Exception]$Exception)

    if ($null -eq $Exception) {
        return ""
    }

    $response = $Exception.Response
    if ($null -eq $response) {
        return ""
    }

    try {
        if ($response.Content -and $response.Content -is [System.Net.Http.HttpContent]) {
            return [string]$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
    }
    catch {
    }

    try {
        $stream = $response.GetResponseStream()
        if ($null -eq $stream) {
            return ""
        }

        try {
            $reader = New-Object System.IO.StreamReader($stream)
            return [string]$reader.ReadToEnd()
        }
        finally {
            if ($reader) {
                $reader.Dispose()
            }
            $stream.Dispose()
        }
    }
    catch {
        return ""
    }
}

function Get-OpenAiFailureDetails {
    param([System.Exception]$Exception)

    if ($null -eq $Exception) {
        return $null
    }

    $statusCode = 0
    $statusDescription = ""
    $errorCode = ""
    $errorType = ""
    $errorParam = ""
    $serviceMessage = ""
    $responseBody = ""
    $requestId = ""
    $category = ""
    $recoverable = $false
    $userMessage = if ([string]::IsNullOrWhiteSpace($Exception.Message)) { "The OpenAI request failed." } else { [string]$Exception.Message }
    $nextStep = "Check script_run.log for the OpenAI response details, then try again or rerun with -ProcessingMode Local."
    $showSetupGuidance = $false

    if ($Exception.Data -and $Exception.Data.Contains("OpenAiFailureCategory")) {
        $category = [string]$Exception.Data["OpenAiFailureCategory"]
        $recoverable = [bool]$Exception.Data["OpenAiRecoverable"]
        $statusCode = [int]$Exception.Data["OpenAiStatusCode"]
        $statusDescription = [string]$Exception.Data["OpenAiStatusDescription"]
        $errorCode = [string]$Exception.Data["OpenAiErrorCode"]
        $errorType = [string]$Exception.Data["OpenAiErrorType"]
        $errorParam = [string]$Exception.Data["OpenAiErrorParam"]
        $serviceMessage = [string]$Exception.Data["OpenAiServiceMessage"]
        $responseBody = Normalize-OpenAiResponseText -Text ([string]$Exception.Data["OpenAiResponseBody"])
        $requestId = [string]$Exception.Data["OpenAiRequestId"]
        $userMessage = [string]$Exception.Data["OpenAiUserMessage"]
        $nextStep = [string]$Exception.Data["OpenAiNextStep"]
        $showSetupGuidance = [bool]$Exception.Data["OpenAiShowSetupGuidance"]
    }
    else {
        $response = $Exception.Response
        if ($response) {
            try {
                if ($response.StatusCode) {
                    $statusCode = [int]$response.StatusCode
                }
            }
            catch {
                $statusCode = 0
            }

            try {
                if ($response.ReasonPhrase) {
                    $statusDescription = [string]$response.ReasonPhrase
                }
            }
            catch {
            }

            if ([string]::IsNullOrWhiteSpace($statusDescription)) {
                try {
                    if ($response.StatusDescription) {
                        $statusDescription = [string]$response.StatusDescription
                    }
                }
                catch {
                }
            }

            $requestId = Get-OpenAiHeaderValue -Headers $response.Headers -Names @("x-request-id", "request-id")
            if ([string]::IsNullOrWhiteSpace($requestId) -and $response.Content) {
                $requestId = Get-OpenAiHeaderValue -Headers $response.Content.Headers -Names @("x-request-id", "request-id")
            }
        }

        $responseBody = Normalize-OpenAiResponseText -Text (Get-OpenAiErrorResponseText -Exception $Exception)
        if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
            try {
                $parsed = $responseBody | ConvertFrom-Json
                if ($parsed.error) {
                    $serviceMessage = [string]$parsed.error.message
                    $errorCode = [string]$parsed.error.code
                    $errorType = [string]$parsed.error.type
                    $errorParam = [string]$parsed.error.param
                }
            }
            catch {
            }
        }

        $messageParts = New-Object System.Collections.Generic.List[string]
        $currentException = $Exception
        while ($currentException) {
            if (-not [string]::IsNullOrWhiteSpace($currentException.Message)) {
                [void]$messageParts.Add([string]$currentException.Message)
            }
            $currentException = $currentException.InnerException
        }
        foreach ($detail in @($serviceMessage, $errorCode, $errorType, $errorParam, $statusDescription, $responseBody)) {
            if (-not [string]::IsNullOrWhiteSpace($detail)) {
                [void]$messageParts.Add([string]$detail)
            }
        }

        $combinedMessage = $messageParts -join " "

        if (($statusCode -eq 429) -and ($combinedMessage -match '(?i)insufficient_quota|quota|billing|credit|credits|balance|payment|billing_hard_limit|billing_not_active')) {
            $category = "Quota"
            $recoverable = $true
            $userMessage = Get-OpenAiQuotaUserMessage
            $nextStep = Get-OpenAiQuotaNextStep
        }
        elseif (($statusCode -eq 401) -or ($combinedMessage -match '(?i)unauthorized|invalid api key|incorrect api key|invalid_api_key|authentication')) {
            $category = "Unauthorized"
            $recoverable = $true
            $userMessage = "OpenAI rejected the request with 401 Unauthorized. The API key is missing, invalid, or not usable for this project."
            $nextStep = Get-OpenAiKeyTroubleshootingText
            $showSetupGuidance = $true
        }
        elseif (($statusCode -eq 403) -or ($combinedMessage -match '(?i)permission denied|permission_denied|forbidden|access denied|does not have access|insufficient permissions|not allowed')) {
            $category = "PermissionDenied"
            $recoverable = $true
            $userMessage = "OpenAI rejected the request because this API key or project does not have permission to call Chat Completions."
            $nextStep = "Check the OpenAI Platform project, model access, and Request permission for Chat Completions, then try again."
            $showSetupGuidance = $true
        }
        elseif (($statusCode -eq 429) -or ($combinedMessage -match '(?i)rate limit|rate_limit|rate_limit_exceeded|too many requests|requests per min|tokens per min|requests per day|tokens per day')) {
            $category = "RateLimit"
            $recoverable = $true
            $userMessage = "OpenAI rate-limited the translation request because too many API requests were sent in a short time (429 Too Many Requests)."
            $nextStep = "Wait a moment, then retry, or rerun with -ProcessingMode Local."
        }
        elseif ($statusCode -ge 500 -and $statusCode -lt 600) {
            $category = "ServerError"
            $recoverable = $true
            $userMessage = ("OpenAI returned a server error ({0})." -f $statusCode)
            $nextStep = "Retry later, or rerun with -ProcessingMode Local."
        }
        elseif ($combinedMessage -match '(?i)timed out|timeout|operation has timed out') {
            $category = "Timeout"
            $recoverable = $true
            $userMessage = "The OpenAI request timed out before translation completed."
            $nextStep = "Retry later, or rerun with -ProcessingMode Local."
        }
        elseif ($combinedMessage -match '(?i)no such host is known|name or service not known|could not resolve|unable to connect|connection.*failed|connection.*closed|network') {
            $category = "Network"
            $recoverable = $true
            $userMessage = "The OpenAI request failed before a response came back from the service."
            $nextStep = "Check the network connection, then retry or rerun with -ProcessingMode Local."
        }
        elseif ($statusCode -gt 0) {
            if (-not [string]::IsNullOrWhiteSpace($serviceMessage)) {
                $userMessage = ("OpenAI returned HTTP {0}. {1}" -f $statusCode, $serviceMessage)
            }
            else {
                $userMessage = ("OpenAI returned HTTP {0}." -f $statusCode)
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($serviceMessage)) {
            $userMessage = ("The OpenAI request failed. {0}" -f $serviceMessage)
        }
    }

    if ([string]::IsNullOrWhiteSpace($category)) {
        $category = "Unknown"
    }

    $categoryLabel = Get-OpenAiFailureCategoryLabel -Category $category
    $diagnosticParts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($categoryLabel)) {
        [void]$diagnosticParts.Add($categoryLabel)
    }
    if ($statusCode -gt 0) {
        if ([string]::IsNullOrWhiteSpace($statusDescription)) {
            [void]$diagnosticParts.Add(("HTTP {0}" -f $statusCode))
        }
        else {
            [void]$diagnosticParts.Add(("HTTP {0} {1}" -f $statusCode, $statusDescription))
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($errorCode)) {
        [void]$diagnosticParts.Add(("error.code={0}" -f $errorCode))
    }
    if (-not [string]::IsNullOrWhiteSpace($errorType)) {
        [void]$diagnosticParts.Add(("error.type={0}" -f $errorType))
    }
    if (-not [string]::IsNullOrWhiteSpace($errorParam)) {
        [void]$diagnosticParts.Add(("error.param={0}" -f $errorParam))
    }
    if (-not [string]::IsNullOrWhiteSpace($requestId)) {
        [void]$diagnosticParts.Add(("request_id={0}" -f $requestId))
    }

    return [PSCustomObject]@{
        Category          = $category
        CategoryLabel     = $categoryLabel
        Recoverable       = $recoverable
        StatusCode        = $statusCode
        StatusDescription = $statusDescription
        ErrorCode         = $errorCode
        ErrorType         = $errorType
        ErrorParam        = $errorParam
        ServiceMessage    = $serviceMessage
        ResponseBody      = $responseBody
        RequestId         = $requestId
        UserMessage       = $userMessage
        NextStep          = $nextStep
        DiagnosticSummary = ($diagnosticParts -join "; ")
        ShowSetupGuidance = $showSetupGuidance
    }
}

function Write-OpenAiSegmentDiagnostic {
    param(
        [string]$DiagnosticsFolder,
        [int]$SegmentIndex,
        [string]$TargetLanguage,
        [string]$Model,
        [string]$Endpoint,
        [string]$RequestBody,
        [int]$StatusCode = 0,
        [string]$ResponseBody = ""
    )

    if ([string]::IsNullOrWhiteSpace($DiagnosticsFolder)) {
        return
    }

    Ensure-Directory $DiagnosticsFolder
    $diagnosticPath = Join-Path $DiagnosticsFolder ("segment_{0:D3}.json" -f $SegmentIndex)
    $payload = [ordered]@{
        timestamp_utc   = (Get-Date).ToUniversalTime().ToString("o")
        segment_index   = $SegmentIndex
        target_language = $TargetLanguage
        model           = $Model
        endpoint        = $Endpoint
        request_body    = $RequestBody
        http_status     = $StatusCode
    }

    if (-not [string]::IsNullOrWhiteSpace($ResponseBody)) {
        $payload.response_body = $ResponseBody
    }

    [PSCustomObject]$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $diagnosticPath -Encoding UTF8
}

function Get-OpenAiProviderFailureText {
    param([PSCustomObject]$FailureDetails)

    if ($null -eq $FailureDetails) {
        return "OpenAI failed"
    }

    $parts = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($FailureDetails.CategoryLabel)) {
        [void]$parts.Add($FailureDetails.CategoryLabel)
    }
    if ($FailureDetails.StatusCode -gt 0) {
        [void]$parts.Add(("HTTP {0}" -f $FailureDetails.StatusCode))
    }
    if (-not [string]::IsNullOrWhiteSpace($FailureDetails.ErrorCode)) {
        [void]$parts.Add(("code={0}" -f $FailureDetails.ErrorCode))
    }
    elseif (-not [string]::IsNullOrWhiteSpace($FailureDetails.ErrorType)) {
        [void]$parts.Add(("type={0}" -f $FailureDetails.ErrorType))
    }

    if ($parts.Count -eq 0) {
        return "OpenAI failed"
    }

    return ("OpenAI failed ({0})" -f ($parts -join ", "))
}

function Write-OpenAiFailureDiagnostics {
    param(
        [string]$TargetLanguage,
        [PSCustomObject]$FailureDetails
    )

    if ($null -eq $FailureDetails) {
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($FailureDetails.DiagnosticSummary)) {
        Write-Log ("OpenAI failure details for '{0}': {1}" -f $TargetLanguage, $FailureDetails.DiagnosticSummary) "WARN"
    }
    if (-not [string]::IsNullOrWhiteSpace($FailureDetails.ServiceMessage)) {
        Write-Log ("OpenAI service message for '{0}': {1}" -f $TargetLanguage, $FailureDetails.ServiceMessage) "WARN"
    }
    if (-not [string]::IsNullOrWhiteSpace($FailureDetails.ResponseBody)) {
        $bodyLine = ("OpenAI raw response body for '{0}': {1}" -f $TargetLanguage, $FailureDetails.ResponseBody)
        if ($bodyLine.Length -le 700 -or -not $script:CurrentLogFile) {
            Write-Log $bodyLine "WARN"
        }
        else {
            Write-Log ("OpenAI raw response body for '{0}' was captured in script_run.log." -f $TargetLanguage) "WARN"
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -LiteralPath $script:CurrentLogFile -Value ("[{0}] [WARN] {1}" -f $timestamp, $bodyLine)
        }
    }
}

function New-OpenAiTranslationException {
    param(
        [string]$TargetLanguage,
        [string]$FailureCategory,
        [string]$UserMessage,
        [string]$NextStep,
        [int]$StatusCode = 0,
        [string]$StatusDescription = "",
        [string]$ErrorCode = "",
        [string]$ErrorType = "",
        [string]$ErrorParam = "",
        [string]$ServiceMessage = "",
        [string]$ResponseBody = "",
        [string]$RequestId = "",
        [bool]$Recoverable = $false,
        [bool]$ShowSetupGuidance = $false,
        [System.Exception]$InnerException = $null
    )

    $message = "OpenAI translation failed for language '$TargetLanguage'. $UserMessage"
    $exception = if ($InnerException) {
        New-Object System.Exception($message, $InnerException)
    }
    else {
        New-Object System.Exception($message)
    }

    $exception.Data["OpenAiFailureCategory"] = $FailureCategory
    $exception.Data["OpenAiRecoverable"] = $Recoverable
    $exception.Data["OpenAiStatusCode"] = $StatusCode
    $exception.Data["OpenAiStatusDescription"] = $StatusDescription
    $exception.Data["OpenAiErrorCode"] = $ErrorCode
    $exception.Data["OpenAiErrorType"] = $ErrorType
    $exception.Data["OpenAiErrorParam"] = $ErrorParam
    $exception.Data["OpenAiServiceMessage"] = $ServiceMessage
    $exception.Data["OpenAiResponseBody"] = $ResponseBody
    $exception.Data["OpenAiRequestId"] = $RequestId
    $exception.Data["OpenAiUserMessage"] = $UserMessage
    $exception.Data["OpenAiNextStep"] = $NextStep
    $exception.Data["OpenAiShowSetupGuidance"] = $ShowSetupGuidance
    return $exception
}

function Get-InteractiveOpenAiRuntimeRecoveryDecision {
    param(
        [string]$TargetLanguage,
        [PSCustomObject]$FailureDetails,
        [bool]$CanUseLocalFallback,
        [string]$LocalFallbackNote = ""
    )

    while ($true) {
        Write-Host ""
        Write-Host ("OpenAI translation for '{0}' hit a recoverable problem." -f $TargetLanguage) -ForegroundColor Yellow
        Write-Host $FailureDetails.UserMessage -ForegroundColor Yellow
        if (-not [string]::IsNullOrWhiteSpace($LocalFallbackNote)) {
            Write-Host $LocalFallbackNote -ForegroundColor DarkYellow
        }
        if ($FailureDetails.ShowSetupGuidance) {
            foreach ($line in (Get-OpenAiSetupInstructionLines -ProviderLabel "OpenAI translation" -Audience "Interactive")) {
                if ([string]::IsNullOrWhiteSpace($line)) {
                    Write-Host ""
                    continue
                }

                if ($line.StartsWith("  ")) {
                    Write-Host $line -ForegroundColor DarkYellow
                    continue
                }

                Write-Host $line -ForegroundColor Yellow
            }
        }

        Write-Host "Choose how to continue:" -ForegroundColor Yellow
        Write-Host "  1. Retry OpenAI for this target" -ForegroundColor Cyan
        if ($CanUseLocalFallback) {
            Write-Host "  2. Switch remaining translation targets to Local" -ForegroundColor Cyan
            Write-Host "  3. Stop translating and keep the completed outputs" -ForegroundColor Cyan
            Write-Host "  4. Cancel this package" -ForegroundColor Cyan
        }
        else {
            Write-Host "  2. Stop translating and keep the completed outputs" -ForegroundColor Cyan
            Write-Host "  3. Cancel this package" -ForegroundColor Cyan
        }

        $choice = if ($CanUseLocalFallback) {
            Read-Host "Type 1, 2, 3, or 4"
        }
        else {
            Read-Host "Type 1, 2, or 3"
        }

        switch ($choice.Trim()) {
            "1" {
                return [PSCustomObject]@{
                    Action         = "Retry"
                    ResolutionNote = ("OpenAI translation for '{0}' was retried after an interactive recovery prompt." -f $TargetLanguage)
                }
            }
            "2" {
                if ($CanUseLocalFallback) {
                    return [PSCustomObject]@{
                        Action         = "UseLocal"
                        ResolutionNote = ("OpenAI translation for '{0}' hit a recoverable problem. Interactive recovery switched the remaining translation targets to Local." -f $TargetLanguage)
                    }
                }

                return [PSCustomObject]@{
                    Action         = "Stop"
                    ResolutionNote = ("OpenAI translation for '{0}' hit a recoverable problem. Interactive recovery kept the completed outputs and stopped further translation work." -f $TargetLanguage)
                }
            }
            "3" {
                if ($CanUseLocalFallback) {
                    return [PSCustomObject]@{
                        Action         = "Stop"
                        ResolutionNote = ("OpenAI translation for '{0}' hit a recoverable problem. Interactive recovery kept the completed outputs and stopped further translation work." -f $TargetLanguage)
                    }
                }

                throw "User canceled the package after an OpenAI translation failure."
            }
            "4" {
                if ($CanUseLocalFallback) {
                    throw "User canceled the package after an OpenAI translation failure."
                }
            }
            default {
                if ($CanUseLocalFallback) {
                    Write-Host "Please type 1, 2, 3, or 4." -ForegroundColor Yellow
                }
                else {
                    Write-Host "Please type 1, 2, or 3." -ForegroundColor Yellow
                }
            }
        }
    }
}

function Get-OpenAiApiKey {
    param(
        [switch]$Required,
        [string]$ProviderLabel = "OpenAI translation"
    )

    $testMode = Get-OpenAiTestMode
    if (-not [string]::IsNullOrWhiteSpace($testMode)) {
        return "__MM_TEST_OPENAI_MODE__"
    }

    $apiKey = [string]$script:SessionOpenAiApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        $keyPreference = Get-OpenAiKeyPreference
        $apiKey = Find-EnvironmentVariableValue -Name $keyPreference.PrimaryVariable
        if ([string]::IsNullOrWhiteSpace($apiKey) -and $keyPreference.AllowLegacyFallback) {
            $apiKey = Find-EnvironmentVariableValue -Name $keyPreference.LegacyVariable
        }
    }

    if ($Required -and [string]::IsNullOrWhiteSpace($apiKey)) {
        Show-OpenAiSetupGuidance -ProviderLabel $ProviderLabel
        throw (Get-OpenAiKeyRequirementText -ProviderLabel $ProviderLabel)
    }

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        return $null
    }

    return $apiKey.Trim()
}

function Test-OpenAiTranslationAvailable {
    if (-not [string]::IsNullOrWhiteSpace((Get-OpenAiTestMode))) {
        return $true
    }

    return -not [string]::IsNullOrWhiteSpace((Get-OpenAiApiKey))
}

function Resolve-TranslationProviderRequest {
    param(
        [string]$RequestedProvider = "Auto",
        [switch]$WasExplicitlySet,
        [switch]$InteractiveMode
    )

    $requestedProviderValue = if ([string]::IsNullOrWhiteSpace($RequestedProvider)) {
        "Auto"
    }
    else {
        $RequestedProvider.Trim()
    }

    $selectionSource = if ($WasExplicitlySet) { "explicit" } else { "default" }
    $effectiveProvider = $requestedProviderValue
    $resolutionNote = $null

    if ($requestedProviderValue -eq "OpenAI" -and -not (Test-OpenAiTranslationAvailable)) {
        if (-not $WasExplicitlySet) {
            $effectiveProvider = "Auto"
            $resolutionNote = "OpenAI was present without an explicit user override, but the selected OpenAI API key is missing. Falling back to Auto."
        }
        elseif ($InteractiveMode) {
            $recoveryDecision = Get-InteractiveOpenAiRecoveryDecision
            $effectiveProvider = $recoveryDecision.EffectiveProvider
            $resolutionNote = $recoveryDecision.ResolutionNote
        }
        else {
            Show-OpenAiSetupGuidance -ProviderLabel "OpenAI translation"
            throw (Get-OpenAiKeyRequirementText)
        }
    }

    return [PSCustomObject]@{
        RequestedProvider = $requestedProviderValue
        EffectiveProvider = $effectiveProvider
        SelectionSource   = $selectionSource
        ResolutionNote    = $resolutionNote
    }
}

function Test-WhisperModelSupportsTranslation {
    param([string]$ModelName)

    if ([string]::IsNullOrWhiteSpace($ModelName)) {
        return $true
    }

    return -not $ModelName.Trim().ToLowerInvariant().EndsWith(".en")
}

function Get-ArgosModuleStatus {
    param(
        [string]$PythonCommand,
        [int]$HeartbeatSeconds = 10
    )

    $probe = Invoke-ExternalCapture `
        -FilePath $PythonCommand `
        -Arguments @("-c", "import argostranslate.translate") `
        -StepName "Argos Translate module check" `
        -IgnoreExitCode `
        -HeartbeatSeconds $HeartbeatSeconds `
        -TimeoutSeconds 120

    return [PSCustomObject]@{
        ModuleInstalled = ($probe.ExitCode -eq 0)
        Error           = [string]$probe.StdErr
    }
}

function Get-TranslationProviderPreflightNotes {
    param(
        [string]$EffectiveProvider,
        [string[]]$TranslationTargets,
        [string]$ModelName,
        [string]$PythonCommand,
        [bool]$InteractiveMode,
        [int]$HeartbeatSeconds = 10
    )

    $normalizedTargets = @($TranslationTargets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($normalizedTargets.Count -eq 0) {
        return @()
    }

    if ($EffectiveProvider -ne "Local") {
        return @()
    }

    if (($normalizedTargets -contains "en") -and -not (Test-WhisperModelSupportsTranslation -ModelName $ModelName)) {
        throw ("Local translation to English needs a multilingual Whisper model. The selected model '{0}' is English-only. Use 'large' or another supported Whisper model that does not end in '.en', or rerun with -ProcessingMode AI." -f $ModelName)
    }

    $needsArgos = (@($normalizedTargets | Where-Object { $_ -ne "en" })).Count -gt 0
    if (-not $needsArgos) {
        return @()
    }

    $argosStatus = Get-ArgosModuleStatus -PythonCommand $PythonCommand -HeartbeatSeconds $HeartbeatSeconds
    if ($argosStatus.ModuleInstalled) {
        return @()
    }

    $messageLines = @(
        "Local translation was selected for one or more non-English targets, but Argos Translate is not installed on this PC.",
        "Argos Translate is required for the Local path when the target language is not English.",
        "Install it with:",
        ("  {0} -m pip install argostranslate" -f (Quote-Argument $PythonCommand)),
        "Once the source language is detected, Media Manglers can then prepare the needed Argos language packages.",
        "You can also rerun with -ProcessingMode AI."
    )

    if (-not $InteractiveMode) {
        throw ($messageLines -join "`n")
    }

    return @(($messageLines -join " "))
}

function Get-ArgosInstallCommandHints {
    param(
        [string]$SourceLanguageCode,
        [string]$TargetLanguageCode
    )

    $pairs = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($SourceLanguageCode) -and -not [string]::IsNullOrWhiteSpace($TargetLanguageCode) -and ($SourceLanguageCode -ne $TargetLanguageCode)) {
        [void]$pairs.Add(("translate-{0}_{1}" -f $SourceLanguageCode, $TargetLanguageCode))
        if ($SourceLanguageCode -ne "en" -and $TargetLanguageCode -ne "en") {
            [void]$pairs.Add(("translate-{0}_{1}" -f $SourceLanguageCode, "en"))
            [void]$pairs.Add(("translate-{0}_{1}" -f "en", $TargetLanguageCode))
        }
    }

    $commands = New-Object System.Collections.Generic.List[string]
    [void]$commands.Add("py -m pip install argostranslate")
    [void]$commands.Add("argospm update")
    foreach ($pair in ($pairs | Select-Object -Unique)) {
        [void]$commands.Add(("argospm install {0}" -f $pair))
    }

    return @($commands | Select-Object -Unique)
}

function Invoke-ArgosProbe {
    param(
        [string]$PythonCommand,
        [string]$SourceLanguageCode,
        [string]$TargetLanguageCode,
        [int]$HeartbeatSeconds = 10
    )

    $tempPy = Join-Path $env:TEMP ("argos_probe_" + [guid]::NewGuid().ToString() + ".py")
    $pyCode = @'
import json
import sys

from_code = sys.argv[1]
to_code = sys.argv[2]
result = {
    "module_installed": False,
    "can_translate": False,
    "installed_languages": [],
    "error": ""
}

try:
    import argostranslate.translate
    result["module_installed"] = True
    languages = argostranslate.translate.get_installed_languages()
    codes = set()
    for language in languages:
        code = getattr(language, "code", "")
        if code:
            codes.add(code)
    result["installed_languages"] = sorted(codes)

    try:
        translation = argostranslate.translate.get_translation_from_codes(from_code, to_code)
        result["can_translate"] = translation is not None
    except Exception as ex:
        result["error"] = str(ex)
except Exception as ex:
    result["error"] = str(ex)

print(json.dumps(result), flush=True)
'@

    Set-Content -LiteralPath $tempPy -Value $pyCode -Encoding UTF8

    try {
        $result = Invoke-ExternalStreaming `
            -FilePath $PythonCommand `
            -Arguments @($tempPy, $SourceLanguageCode, $TargetLanguageCode) `
            -StepName ("Argos probe ({0}->{1})" -f $SourceLanguageCode, $TargetLanguageCode) `
            -IgnoreExitCode `
            -HeartbeatSeconds $HeartbeatSeconds `
            -TimeoutSeconds 300

        $parsedJsonLine = ($result.StdOut -split "`r?`n" | Where-Object { $_.Trim().StartsWith("{") -and $_.Trim().EndsWith("}") } | Select-Object -Last 1)
        if (-not $parsedJsonLine) {
            return [PSCustomObject]@{
                ModuleInstalled   = $false
                CanTranslate      = $false
                InstalledLanguages = @()
                Error             = "Argos probe did not return a parsable result."
            }
        }

        $parsed = $parsedJsonLine | ConvertFrom-Json
        return [PSCustomObject]@{
            ModuleInstalled    = [bool]$parsed.module_installed
            CanTranslate       = [bool]$parsed.can_translate
            InstalledLanguages = @($parsed.installed_languages)
            Error              = [string]$parsed.error
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPy) {
            Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-ArgosTranslationSupport {
    param(
        [string]$PythonCommand,
        [string]$SourceLanguageCode,
        [string]$TargetLanguageCode,
        [int]$HeartbeatSeconds = 10
    )

    $probe = Invoke-ArgosProbe `
        -PythonCommand $PythonCommand `
        -SourceLanguageCode $SourceLanguageCode `
        -TargetLanguageCode $TargetLanguageCode `
        -HeartbeatSeconds $HeartbeatSeconds

    if (-not $probe.ModuleInstalled) {
        $pipResult = Invoke-ExternalStreaming `
            -FilePath $PythonCommand `
            -Arguments @("-m", "pip", "install", "argostranslate") `
            -StepName "Install Argos Translate" `
            -IgnoreExitCode `
            -HeartbeatSeconds $HeartbeatSeconds `
            -TimeoutSeconds 1800

        if ($pipResult.ExitCode -ne 0) {
            throw "Could not install Argos Translate with pip. See script_run.log for the exact pip error."
        }
    }

    $tempPy = Join-Path $env:TEMP ("argos_install_" + [guid]::NewGuid().ToString() + ".py")
    $pyCode = @'
import json
import sys
import traceback

from_code = sys.argv[1]
to_code = sys.argv[2]

result = {
    "success": False,
    "attempted_pairs": [],
    "installed_pairs": [],
    "error": ""
}

def log(msg):
    print(msg, flush=True)

try:
    import argostranslate.package
    import argostranslate.translate
except Exception:
    traceback.print_exc(file=sys.stderr)
    sys.exit(10)

def add_pair(pairs, seen, source_code, target_code):
    if not source_code or not target_code or source_code == target_code:
        return
    key = (source_code, target_code)
    if key in seen:
        return
    seen.add(key)
    pairs.append(key)

def install_pair(available_packages, source_code, target_code):
    package_to_install = next(
        (
            package
            for package in available_packages
            if getattr(package, "from_code", "") == source_code and getattr(package, "to_code", "") == target_code
        ),
        None,
    )
    if package_to_install is None:
        raise RuntimeError(f"No Argos package index entry found for {source_code}->{target_code}")

    download_path = package_to_install.download()
    argostranslate.package.install_from_path(download_path)

try:
    pairs = []
    seen = set()
    add_pair(pairs, seen, from_code, to_code)
    if from_code != "en" and to_code != "en":
        add_pair(pairs, seen, from_code, "en")
        add_pair(pairs, seen, "en", to_code)

    log("[PY] Updating Argos package index...")
    argostranslate.package.update_package_index()
    available_packages = argostranslate.package.get_available_packages()

    for source_code, target_code in pairs:
        result["attempted_pairs"].append({"from": source_code, "to": target_code})
        try:
            log(f"[PY] Installing Argos package {source_code}->{target_code}...")
            install_pair(available_packages, source_code, target_code)
            result["installed_pairs"].append({"from": source_code, "to": target_code})
        except Exception as ex:
            log(f"[PY] Install note for {source_code}->{target_code}: {ex}")

    try:
        translation = argostranslate.translate.get_translation_from_codes(from_code, to_code)
        result["success"] = translation is not None
        if not result["success"]:
            result["error"] = f"Argos still cannot translate {from_code}->{to_code} after installation."
    except Exception as ex:
        result["error"] = str(ex)

    print(json.dumps(result), flush=True)
except Exception:
    traceback.print_exc(file=sys.stderr)
    sys.exit(20)
'@

    Set-Content -LiteralPath $tempPy -Value $pyCode -Encoding UTF8

    try {
        $result = Invoke-ExternalStreaming `
            -FilePath $PythonCommand `
            -Arguments @($tempPy, $SourceLanguageCode, $TargetLanguageCode) `
            -StepName ("Install Argos language support ({0}->{1})" -f $SourceLanguageCode, $TargetLanguageCode) `
            -IgnoreExitCode `
            -HeartbeatSeconds $HeartbeatSeconds `
            -TimeoutSeconds 3600

        if ($result.ExitCode -ne 0) {
            throw "Argos package installation failed. See script_run.log for the exact Python error."
        }

        $parsedJsonLine = ($result.StdOut -split "`r?`n" | Where-Object { $_.Trim().StartsWith("{") -and $_.Trim().EndsWith("}") } | Select-Object -Last 1)
        if (-not $parsedJsonLine) {
            throw "Argos package installation did not return a parsable result. See script_run.log."
        }

        $parsed = $parsedJsonLine | ConvertFrom-Json
        if (-not [bool]$parsed.success) {
            $errorMessage = [string]$parsed.error
            if ([string]::IsNullOrWhiteSpace($errorMessage)) {
                $errorMessage = "Argos did not report a usable translation route after installation."
            }

            throw $errorMessage
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempPy) {
            Remove-Item -LiteralPath $tempPy -Force -ErrorAction SilentlyContinue
        }
    }
}

function Ensure-ArgosTranslationSupport {
    param(
        [string]$PythonCommand,
        [string]$SourceLanguageCode,
        [string]$TargetLanguageCode,
        [bool]$InteractiveMode,
        [int]$HeartbeatSeconds = 10
    )

    $sourceCode = [string]$SourceLanguageCode
    $targetCode = [string]$TargetLanguageCode

    if ([string]::IsNullOrWhiteSpace($sourceCode) -or $sourceCode -eq "unknown") {
        throw "Local translation needs a known source language code. Try -ProcessingMode AI, or rerun with -Language if you know the source language."
    }

    $probe = Invoke-ArgosProbe `
        -PythonCommand $PythonCommand `
        -SourceLanguageCode $sourceCode `
        -TargetLanguageCode $targetCode `
        -HeartbeatSeconds $HeartbeatSeconds

    if ($probe.CanTranslate) {
        return "ready"
    }

    $sourceDisplayName = Get-LanguageDisplayName -Code $sourceCode
    $targetDisplayName = Get-LanguageDisplayName -Code $targetCode
    $commandHints = @(Get-ArgosInstallCommandHints -SourceLanguageCode $sourceCode -TargetLanguageCode $targetCode)

    $messageLines = @()
    if (-not $probe.ModuleInstalled) {
        $messageLines += "Local translation is missing Argos Translate."
    }
    else {
        $messageLines += ("Local translation does not have the needed Argos language package for {0} -> {1} yet." -f $sourceDisplayName, $targetDisplayName)
    }
    $messageLines += ("This unlocks a free local translation path for {0} -> {1} without needing an OpenAI account." -f $sourceDisplayName, $targetDisplayName)
    $messageLines += "OpenAI is usually smoother, but Local keeps the translated transcript on this PC."
    $messageLines += "Suggested install commands:"
    foreach ($command in $commandHints) {
        $messageLines += ("  {0}" -f $command)
    }

    if (-not $InteractiveMode) {
        throw ($messageLines -join "`n")
    }

    Write-Host ""
    foreach ($line in $messageLines) {
        Write-Host $line -ForegroundColor Yellow
    }
    Write-Host ""

    while ($true) {
        $choice = Read-Host "Type I to install now, S to skip this translation, or C to cancel"
        switch ($choice.Trim().ToLowerInvariant()) {
            "i" {
                Install-ArgosTranslationSupport `
                    -PythonCommand $PythonCommand `
                    -SourceLanguageCode $sourceCode `
                    -TargetLanguageCode $targetCode `
                    -HeartbeatSeconds $HeartbeatSeconds
                return "installed"
            }
            "s" {
                return "skip"
            }
            "c" {
                throw "User canceled while preparing local translation support."
            }
            default {
                Write-Host "Please type I, S, or C." -ForegroundColor Yellow
            }
        }
    }
}

function Resolve-TranslationTargetProvider {
    param(
        [string]$TranslationMode,
        [string]$TargetLanguage,
        [string]$DetectedLanguage,
        [string]$ModelName,
        [string]$PythonCommand,
        [bool]$InteractiveMode,
        [int]$HeartbeatSeconds = 10
    )

    if ($TargetLanguage -eq $DetectedLanguage) {
        return [PSCustomObject]@{
            Action = "ready"
            Provider = "Original transcript copy"
            Note = ""
        }
    }

    if ($TranslationMode -eq "OpenAI") {
        return [PSCustomObject]@{
            Action = "ready"
            Provider = "OpenAI"
            Note = ""
        }
    }

    if ($TranslationMode -eq "Local") {
        if ($TargetLanguage -eq "en") {
            if (-not (Test-WhisperModelSupportsTranslation -ModelName $ModelName)) {
                throw "Local translation to English needs a multilingual Whisper model. Use 'large' or another supported Whisper model that does not end in '.en', or use -ProcessingMode AI."
            }

            return [PSCustomObject]@{
                Action = "ready"
                Provider = "Local (Whisper audio translation)"
                Note = ""
            }
        }

        $argosStatus = Ensure-ArgosTranslationSupport `
            -PythonCommand $PythonCommand `
            -SourceLanguageCode $DetectedLanguage `
            -TargetLanguageCode $TargetLanguage `
            -InteractiveMode:$InteractiveMode `
            -HeartbeatSeconds $HeartbeatSeconds

        if ($argosStatus -eq "skip") {
            return [PSCustomObject]@{
                Action = "skip"
                Provider = "Local (Argos Translate)"
                Note = ("Skipping translation target '{0}' because local Argos support was not installed." -f $TargetLanguage)
            }
        }

        return [PSCustomObject]@{
            Action = "ready"
            Provider = "Local (Argos Translate)"
            Note = ""
        }
    }

    if ($TranslationMode -eq "Auto") {
        if (Test-OpenAiTranslationAvailable) {
            return [PSCustomObject]@{
                Action = "ready"
                Provider = "OpenAI"
                Note = ""
            }
        }

        return Resolve-TranslationTargetProvider `
            -TranslationMode "Local" `
            -TargetLanguage $TargetLanguage `
            -DetectedLanguage $DetectedLanguage `
            -ModelName $ModelName `
            -PythonCommand $PythonCommand `
            -InteractiveMode:$InteractiveMode `
            -HeartbeatSeconds $HeartbeatSeconds
    }

    throw "Unsupported translation mode '$TranslationMode'."
}

function Invoke-OpenAiSegmentTranslation {
    param(
        [array]$Segments,
        [string]$SourceLanguage,
        [string]$TargetLanguage,
        [string]$Model,
        [int]$HeartbeatSeconds = 10,
        [string]$DiagnosticsFolder = ""
    )

    $apiKey = Get-OpenAiApiKey -Required -ProviderLabel "OpenAI translation"
    $testMode = Get-OpenAiTestMode
    $endpoint = "https://api.openai.com/v1/chat/completions"
    if (-not [string]::IsNullOrWhiteSpace($testMode) -and -not $script:OpenAiTestModeLogged) {
        Write-Log ("MM_TEST_OPENAI_MODE='{0}' active. OpenAI translation calls are being simulated for this run." -f $testMode) "WARN"
        $script:OpenAiTestModeLogged = $true
    }

    $headers = @{
        Authorization = "Bearer $apiKey"
    }
    $contentType = "application/json; charset=utf-8"

    $translatedSegments = @()
    $lastProgress = Get-Date
    $segmentIndex = 0
    foreach ($segment in $Segments) {
        $segmentIndex += 1
        $text = [string]$segment.text
        if ([string]::IsNullOrWhiteSpace($text)) {
            $translatedSegments += [PSCustomObject]@{
                id    = $segment.id
                start = $segment.start
                end   = $segment.end
                text  = ""
            }
            continue
        }

        if (((Get-Date) - $lastProgress).TotalSeconds -ge $HeartbeatSeconds) {
            Write-Log ("OpenAI translation still working... {0}/{1} segments translated" -f $segmentIndex, $Segments.Count)
            $lastProgress = Get-Date
        }

        $userPrompt = if ([string]::IsNullOrWhiteSpace($SourceLanguage)) {
            "Translate this spoken transcript segment into $TargetLanguage. Return only the translated text.`n`n$text"
        }
        else {
            "Translate this spoken transcript segment from $SourceLanguage into $TargetLanguage. Return only the translated text.`n`n$text"
        }

        $body = @{
            model = $Model
            messages = @(
                @{
                    role = "system"
                    content = "You translate transcript segments. Return only the translated text with no commentary, labels, or quotes."
                },
                @{
                    role = "user"
                    content = $userPrompt
                }
            )
        } | ConvertTo-Json -Depth 6

        try {
            if ($testMode -eq "success") {
                $translatedText = ("[MM_TEST_OPENAI_SUCCESS:{0}] {1}" -f $TargetLanguage, $text).Trim()
            }
            elseif ($testMode -eq "unauthorized") {
                $responseBody = '{"error":{"message":"Incorrect API key provided: sk-test-invalid","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}'
                throw (New-OpenAiTranslationException `
                        -TargetLanguage $TargetLanguage `
                        -FailureCategory "Unauthorized" `
                        -UserMessage "OpenAI rejected the request with 401 Unauthorized. The API key is missing, invalid, or not usable for this project." `
                        -NextStep (Get-OpenAiKeyTroubleshootingText) `
                        -StatusCode 401 `
                        -StatusDescription "Unauthorized" `
                        -ErrorCode "invalid_api_key" `
                        -ErrorType "invalid_request_error" `
                        -ServiceMessage "Incorrect API key provided: sk-test-invalid" `
                        -ResponseBody $responseBody `
                        -Recoverable:$true `
                        -ShowSetupGuidance:$true)
            }
            elseif ($testMode -eq "permission_denied") {
                $responseBody = '{"error":{"message":"You do not have permission to access Chat Completions for this project.","type":"invalid_request_error","param":"model","code":"permission_denied"}}'
                throw (New-OpenAiTranslationException `
                        -TargetLanguage $TargetLanguage `
                        -FailureCategory "PermissionDenied" `
                        -UserMessage "OpenAI rejected the request because this API key or project does not have permission to call Chat Completions." `
                        -NextStep "Check the OpenAI Platform project, model access, and Request permission for Chat Completions, then try again." `
                        -StatusCode 403 `
                        -StatusDescription "Forbidden" `
                        -ErrorCode "permission_denied" `
                        -ErrorType "invalid_request_error" `
                        -ErrorParam "model" `
                        -ServiceMessage "You do not have permission to access Chat Completions for this project." `
                        -ResponseBody $responseBody `
                        -Recoverable:$true `
                        -ShowSetupGuidance:$true)
            }
            elseif ($testMode -eq "rate_limit") {
                $responseBody = '{"error":{"message":"Rate limit reached for requests per min. Please try again in 20s.","type":"rate_limit_error","param":null,"code":"rate_limit_exceeded"}}'
                throw (New-OpenAiTranslationException `
                        -TargetLanguage $TargetLanguage `
                        -FailureCategory "RateLimit" `
                        -UserMessage "OpenAI rate-limited the translation request because too many API requests were sent in a short time (429 Too Many Requests)." `
                        -NextStep "Wait a moment, then retry, or rerun with -ProcessingMode Local." `
                        -StatusCode 429 `
                        -StatusDescription "Too Many Requests" `
                        -ErrorCode "rate_limit_exceeded" `
                        -ErrorType "rate_limit_error" `
                        -ServiceMessage "Rate limit reached for requests per min. Please try again in 20s." `
                        -ResponseBody $responseBody `
                        -Recoverable:$true)
            }
            elseif ($testMode -eq "quota") {
                $responseBody = '{"error":{"message":"You exceeded your current quota, please check your plan and billing details.","type":"insufficient_quota","param":null,"code":"insufficient_quota"}}'
                throw (New-OpenAiTranslationException `
                        -TargetLanguage $TargetLanguage `
                        -FailureCategory "Quota" `
                        -UserMessage (Get-OpenAiQuotaUserMessage) `
                        -NextStep (Get-OpenAiQuotaNextStep) `
                        -StatusCode 429 `
                        -StatusDescription "Too Many Requests" `
                        -ErrorCode "insufficient_quota" `
                        -ErrorType "insufficient_quota" `
                        -ServiceMessage "You exceeded your current quota, please check your plan and billing details." `
                        -ResponseBody $responseBody `
                        -Recoverable:$true)
            }
            elseif ($testMode -eq "server_error") {
                $responseBody = '{"error":{"message":"The server had an error while processing your request.","type":"server_error","param":null,"code":null}}'
                throw (New-OpenAiTranslationException `
                        -TargetLanguage $TargetLanguage `
                        -FailureCategory "ServerError" `
                        -UserMessage "OpenAI returned a server error (500)." `
                        -NextStep "Retry later, or rerun with -ProcessingMode Local." `
                        -StatusCode 500 `
                        -StatusDescription "Internal Server Error" `
                        -ErrorType "server_error" `
                        -ServiceMessage "The server had an error while processing your request." `
                        -ResponseBody $responseBody `
                        -Recoverable:$true)
            }
            elseif ($testMode -eq "timeout") {
                throw (New-OpenAiTranslationException `
                        -TargetLanguage $TargetLanguage `
                        -FailureCategory "Timeout" `
                        -UserMessage "The OpenAI request timed out before translation completed." `
                        -NextStep "Retry later, or rerun with -ProcessingMode Local." `
                        -Recoverable:$true)
            }
            elseif ($testMode -eq "network") {
                throw (New-OpenAiTranslationException `
                        -TargetLanguage $TargetLanguage `
                        -FailureCategory "Network" `
                        -UserMessage "The OpenAI request failed before a response came back from the service." `
                        -NextStep "Check the network connection, then retry or rerun with -ProcessingMode Local." `
                        -Recoverable:$true)
            }
            else {
                $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $response = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -ContentType $contentType -Body $bodyBytes
                $translatedText = [string]$response.choices[0].message.content
                Write-OpenAiSegmentDiagnostic `
                    -DiagnosticsFolder $DiagnosticsFolder `
                    -SegmentIndex $segmentIndex `
                    -TargetLanguage $TargetLanguage `
                    -Model $Model `
                    -Endpoint $endpoint `
                    -RequestBody $body `
                    -StatusCode 200
            }
        }
        catch {
            $failureDetails = Get-OpenAiFailureDetails -Exception $_.Exception
            if ($failureDetails) {
                Write-OpenAiSegmentDiagnostic `
                    -DiagnosticsFolder $DiagnosticsFolder `
                    -SegmentIndex $segmentIndex `
                    -TargetLanguage $TargetLanguage `
                    -Model $Model `
                    -Endpoint $endpoint `
                    -RequestBody $body `
                    -StatusCode $failureDetails.StatusCode `
                    -ResponseBody $(if (-not [string]::IsNullOrWhiteSpace($failureDetails.RawResponseBody)) { $failureDetails.RawResponseBody } else { $failureDetails.ResponseBody })
                Write-OpenAiFailureDiagnostics -TargetLanguage $TargetLanguage -FailureDetails $failureDetails
                if ($_.Exception.Data -and $_.Exception.Data.Contains("OpenAiFailureCategory")) {
                    throw $_.Exception
                }

                throw (New-OpenAiTranslationException `
                        -TargetLanguage $TargetLanguage `
                        -FailureCategory $failureDetails.Category `
                        -UserMessage $failureDetails.UserMessage `
                        -NextStep $failureDetails.NextStep `
                        -StatusCode $failureDetails.StatusCode `
                        -StatusDescription $failureDetails.StatusDescription `
                        -ErrorCode $failureDetails.ErrorCode `
                        -ErrorType $failureDetails.ErrorType `
                        -ErrorParam $failureDetails.ErrorParam `
                        -ServiceMessage $failureDetails.ServiceMessage `
                        -ResponseBody $failureDetails.ResponseBody `
                        -RequestId $failureDetails.RequestId `
                        -Recoverable:$failureDetails.Recoverable `
                        -ShowSetupGuidance:$failureDetails.ShowSetupGuidance `
                        -InnerException $_.Exception)
            }

            throw "OpenAI translation failed for language '$TargetLanguage'. $($_.Exception.Message)"
        }

        $translatedSegments += [PSCustomObject]@{
            id    = $segment.id
            start = $segment.start
            end   = $segment.end
            text  = $translatedText.Trim()
        }
    }

    return $translatedSegments
}

function Invoke-ArgosSegmentTranslation {
    param(
        [string]$PythonCommand,
        [array]$Segments,
        [string]$SourceLanguageCode,
        [string]$TargetLanguageCode,
        [int]$HeartbeatSeconds = 10
    )

    $tempPy = Join-Path $env:TEMP ("argos_translate_" + [guid]::NewGuid().ToString() + ".py")
    $tempInputJson = Join-Path $env:TEMP ("argos_translate_input_" + [guid]::NewGuid().ToString() + ".json")
    $tempOutputJson = Join-Path $env:TEMP ("argos_translate_output_" + [guid]::NewGuid().ToString() + ".json")

    $segmentsPayload = [PSCustomObject]@{
        segments = @(
            $Segments | ForEach-Object {
                [PSCustomObject]@{
                    id    = $_.id
                    start = $_.start
                    end   = $_.end
                    text  = $_.text
                }
            }
        )
    }
    $segmentsPayload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tempInputJson -Encoding UTF8

    $pyCode = @'
import json
import sys
import traceback

input_path = sys.argv[1]
output_path = sys.argv[2]
from_code = sys.argv[3]
to_code = sys.argv[4]

def log(msg):
    print(msg, flush=True)

try:
    import argostranslate.translate
except Exception:
    traceback.print_exc(file=sys.stderr)
    sys.exit(10)

try:
    with open(input_path, "r", encoding="utf-8-sig") as f:
        payload = json.load(f)

    translation = argostranslate.translate.get_translation_from_codes(from_code, to_code)
    segments = payload.get("segments") or []
    translated_segments = []

    for index, segment in enumerate(segments, start=1):
        text = (segment.get("text") or "").strip()
        translated_text = translation.translate(text) if text else ""
        translated_segments.append({
            "id": segment.get("id"),
            "start": segment.get("start"),
            "end": segment.get("end"),
            "text": translated_text.strip()
        })

        if index == 1 or index % 25 == 0 or index == len(segments):
            log(f"[PY] Argos translation still working... {index}/{len(segments)} segments translated")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({"segments": translated_segments}, f, ensure_ascii=False, indent=2)

    print(json.dumps({
        "output_path": output_path,
        "segments_count": len(translated_segments)
    }), flush=True)
except Exception:
    traceback.print_exc(file=sys.stderr)
    sys.exit(20)
'@

    Set-Content -LiteralPath $tempPy -Value $pyCode -Encoding UTF8

    try {
        $result = Invoke-ExternalStreaming `
            -FilePath $PythonCommand `
            -Arguments @($tempPy, $tempInputJson, $tempOutputJson, $SourceLanguageCode, $TargetLanguageCode) `
            -StepName ("Argos translation ({0}->{1})" -f $SourceLanguageCode, $TargetLanguageCode) `
            -IgnoreExitCode `
            -HeartbeatSeconds $HeartbeatSeconds `
            -TimeoutSeconds 3600

        if ($result.ExitCode -ne 0) {
            throw "Argos translation failed. See script_run.log for the exact Python error."
        }

        if (-not (Test-Path -LiteralPath $tempOutputJson)) {
            throw "Argos translation did not produce an output file."
        }

        $payload = Get-Content -LiteralPath $tempOutputJson -Raw | ConvertFrom-Json
        return @(
            $payload.segments | ForEach-Object {
                [PSCustomObject]@{
                    id    = $_.id
                    start = [double]$_.start
                    end   = [double]$_.end
                    text  = [string]$_.text
                }
            }
        )
    }
    finally {
        foreach ($tempPath in @($tempPy, $tempInputJson, $tempOutputJson)) {
            if (Test-Path -LiteralPath $tempPath) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Get-LanguageDisplayName {
    param([string]$Code)

    if ([string]::IsNullOrWhiteSpace($Code)) {
        return ""
    }

    switch ($Code.Trim().ToLowerInvariant()) {
        "en" { return "English" }
        "es" { return "Spanish" }
        "fr" { return "French" }
        "de" { return "German" }
        "it" { return "Italian" }
        "pt" { return "Portuguese" }
        "ja" { return "Japanese" }
        "ko" { return "Korean" }
        "zh" { return "Chinese" }
        "ar" { return "Arabic" }
        "ru" { return "Russian" }
        default { return $Code.Trim() }
    }
}

function Export-ReviewAudioMp3 {
    param(
        [string]$FFmpegExe,
        [string]$InputMedia,
        [string]$OutputAudio,
        [int]$HeartbeatSeconds = 10
    )

    if (Test-Path -LiteralPath $OutputAudio) {
        Write-Log "Review audio already exists. Skipping build."
        return "SKIPPED_EXISTING"
    }

    $result = Invoke-ExternalCapture `
        -FilePath $FFmpegExe `
        -Arguments @("-y", "-i", $InputMedia, "-vn", "-c:a", "libmp3lame", "-b:a", "192k", $OutputAudio) `
        -StepName "Review audio build" `
        -HeartbeatSeconds $HeartbeatSeconds

    if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $OutputAudio)) {
        throw "Review audio build failed."
    }

    return "CREATED"
}

function Get-TranscriptSegments {
    param([string]$TranscriptJsonPath)

    if (-not (Test-Path -LiteralPath $TranscriptJsonPath)) {
        throw "Transcript JSON not found: $TranscriptJsonPath"
    }

    $payload = Get-Content -LiteralPath $TranscriptJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $segments = @()
    $index = 0
    foreach ($segment in @($payload.segments)) {
        $segments += [PSCustomObject]@{
            id    = if ($null -ne $segment.id) { [int]$segment.id } else { $index }
            start = [double]$segment.start
            end   = [double]$segment.end
            text  = [string]$segment.text
        }
        $index += 1
    }

    return [PSCustomObject]@{
        Language       = [string]$payload.language
        SourceLanguage = [string]$payload.source_language
        Segments       = $segments
    }
}

function Build-SegmentIndex {
    param(
        [array]$Segments,
        [string]$SegmentIndexCsv
    )

    if (-not $Segments -or $Segments.Count -eq 0) {
        throw "No transcript segments were available to index."
    }

    $rows = @()
    $segmentNumber = 0
    foreach ($segment in $Segments) {
        $segmentNumber += 1
        $rows += [PSCustomObject]@{
            segment_number = $segmentNumber
            start_seconds  = ([math]::Round([double]$segment.start, 3)).ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
            end_seconds    = ([math]::Round([double]$segment.end, 3)).ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
            start_time     = Convert-ToSrtTimestamp -Seconds ([double]$segment.start)
            end_time       = Convert-ToSrtTimestamp -Seconds ([double]$segment.end)
            original_text  = ([string]$segment.text).Trim()
        }
    }

    $rows | Export-Csv -LiteralPath $SegmentIndexCsv -NoTypeInformation -Encoding UTF8
    return $rows.Count
}

function Get-BenchmarkSampleDurationSeconds {
    param(
        [string]$FFprobeExe,
        [string]$MediaPath,
        [double]$MaximumSampleSeconds
    )

    $duration = Get-VideoDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $MediaPath
    if ($duration -le 0) {
        return 0.0
    }

    return [math]::Min($duration, $MaximumSampleSeconds)
}

function Get-BenchmarkAudioEncodeSeconds {
    param(
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [string]$MediaPath
    )

    $tempOut = Join-Path $env:TEMP ("audio_bench_" + [guid]::NewGuid().ToString() + ".mp3")
    $sampleSeconds = Get-BenchmarkSampleDurationSeconds -FFprobeExe $FFprobeExe -MediaPath $MediaPath -MaximumSampleSeconds 45.0

    try {
        if ($sampleSeconds -le 0) {
            return $null
        }

        $sampleText = $sampleSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $result = Invoke-ExternalCapture `
            -FilePath $FFmpegExe `
            -Arguments @("-y", "-ss", "0", "-t", $sampleText, "-i", $MediaPath, "-vn", "-c:a", "libmp3lame", "-b:a", "192k", $tempOut) `
            -StepName "Benchmark review audio build"

        return [PSCustomObject]@{ Elapsed = $result.DurationSeconds; Sample = $sampleSeconds }
    }
    finally {
        if (Test-Path -LiteralPath $tempOut) {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-BestEffortAudioEstimate {
    param(
        [array]$AudioItems,
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [bool]$CanUseWhisperGpu,
        [string[]]$TranslationTargets
    )

    Write-Phase -Name "Estimate" -Detail "Running best-effort runtime estimate. Failures here will not stop processing."

    $warnings = @()

    try {
        $totalDuration = 0.0
        foreach ($audioItem in $AudioItems) {
            $totalDuration += Get-VideoDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $audioItem.FullName
        }

        if ($totalDuration -le 0) {
            $warnings += "Could not determine media duration for estimation."
            return $null
        }

        $sampleAudio = $AudioItems | Select-Object -First 1
        $audioEstimate = $null

        try {
            $audioBench = Get-BenchmarkAudioEncodeSeconds -FFmpegExe $FFmpegExe -FFprobeExe $FFprobeExe -MediaPath $sampleAudio.FullName
            if ($audioBench -and $audioBench.Sample -gt 0) {
                $audioEstimate = $totalDuration * ($audioBench.Elapsed / $audioBench.Sample)
            }
        }
        catch {
            $warnings += "Review audio benchmark failed: $($_.Exception.Message)"
        }

        if ($null -eq $audioEstimate) {
            $audioEstimate = $totalDuration * 0.04
            $warnings += "Review audio estimate used a heuristic rather than a benchmark."
        }

        $whisperMultiplier = if ($CanUseWhisperGpu) { 0.55 } else { 1.65 }
        $whisperEstimate = [math]::Max(10.0, $totalDuration * $whisperMultiplier)

        $translationTargetsNormalized = @($TranslationTargets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $englishTranslationEstimate = if ($translationTargetsNormalized -contains "en") {
            [math]::Max(5.0, $totalDuration * (if ($CanUseWhisperGpu) { 0.45 } else { 1.20 }))
        }
        else {
            0.0
        }

        $nonEnglishTargets = @($translationTargetsNormalized | Where-Object { $_ -ne "en" })
        $openAiTranslationEstimate = if ($nonEnglishTargets.Count -gt 0) {
            [math]::Max(5.0, $totalDuration * 0.18 * $nonEnglishTargets.Count)
        }
        else {
            0.0
        }

        if ($translationTargetsNormalized.Count -gt 0) {
            $warnings += "Translation estimates use heuristics because the target language path depends on transcript content and provider response times."
        }

        $indexEstimate = [math]::Max(2.0, $totalDuration * 0.01)
        $totalEstimate = $audioEstimate + $whisperEstimate + $englishTranslationEstimate + $openAiTranslationEstimate + $indexEstimate
        $warnings += ("Whisper estimate uses a {0} heuristic rather than a transcription benchmark so estimation can never kill the real run." -f $(if ($CanUseWhisperGpu) { "GPU" } else { "CPU" }))

        return [PSCustomObject]@{
            TotalDurationSeconds       = $totalDuration
            AudioEstimateSeconds       = [math]::Round($audioEstimate)
            WhisperEstimateSeconds     = [math]::Round($whisperEstimate)
            TranslationEstimateSeconds = [math]::Round($englishTranslationEstimate + $openAiTranslationEstimate)
            IndexEstimateSeconds       = [math]::Round($indexEstimate)
            TotalEstimateSeconds       = [math]::Round($totalEstimate)
            Warnings                   = $warnings
        }
    }
    catch {
        Write-Log "Estimate step failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Process-Audio {
    param(
        [string]$AudioPath,
        [string]$BaseOutputFolder,
        [string]$FFmpegExe,
        [string]$FFprobeExe,
        [string]$PythonCommand,
        [string]$ModelName,
        [string]$LanguageCode,
        [string[]]$TranslationTargets,
        [string]$SourceInfoJsonPath,
        [bool]$DoCopyRaw,
        [string]$SummaryCsv,
        [bool]$CanUseWhisperGpu,
        [bool]$InteractiveMode,
        [string]$RequestedProcessingMode,
        [string]$ProcessingModeSelectionSource,
        [string]$ProcessingModeResolutionNote,
        [string]$ProcessingMode,
        [string]$OpenAiProject,
        [string]$RequestedTranslationProvider,
        [string]$TranslationProviderSelectionSource,
        [string]$TranslationProviderResolutionNote,
        [string]$TranslationProvider,
        [string]$OpenAiModel,
        [string]$OpenAiTranscriptionModel,
        [int]$HeartbeatSeconds = 10
    )

    $AudioPath = Normalize-UserPath -Path $AudioPath
    if (-not (Test-Path -LiteralPath $AudioPath)) {
        throw "Input audio not found: $AudioPath"
    }

    $audioItem = Get-Item -LiteralPath $AudioPath
    $safeBaseName = Get-SafeFolderName $audioItem.BaseName
    if ([string]::IsNullOrWhiteSpace($safeBaseName)) {
        $safeBaseName = "audio_package"
    }

    $audioOutputRoot = Join-Path $BaseOutputFolder $safeBaseName
    $rawFolder = Join-Path $audioOutputRoot "raw"
    $audioFolder = Join-Path $audioOutputRoot "audio"
    $transcriptFolder = Join-Path $audioOutputRoot "transcript"
    $translationsFolder = Join-Path $audioOutputRoot "translations"
    $commentsFolder = Join-Path $audioOutputRoot "comments"
    $rawAudioPath = Join-Path $rawFolder $audioItem.Name
    $reviewAudioPath = Join-Path $audioFolder "review_audio.mp3"
    $originalTranscriptSrt = Join-Path $transcriptFolder "transcript_original.srt"
    $originalTranscriptJson = Join-Path $transcriptFolder "transcript_original.json"
    $originalTranscriptText = Join-Path $transcriptFolder "transcript_original.txt"
    $segmentIndexCsv = Join-Path $audioOutputRoot "segment_index.csv"
    $readmeFile = Join-Path $audioOutputRoot "README_FOR_CODEX.txt"
    $logFile = Join-Path $audioOutputRoot "script_run.log"
    $openAiDiagnosticsFolder = ""

    Ensure-Directory $audioOutputRoot
    Ensure-Directory $audioFolder
    Ensure-Directory $transcriptFolder

    $script:CurrentLogFile = $logFile
    Set-Content -LiteralPath $script:CurrentLogFile -Value ("Audio Mangler log - {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ("Processing: {0}" -f $audioItem.FullName) -ForegroundColor Cyan
    Write-Host ("Output:     {0}" -f $audioOutputRoot) -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Log "Processing audio: $($audioItem.FullName)"
    Write-Log "Output folder: $audioOutputRoot"
    $processingModeSummary = Get-ProcessingModeSummary -EffectiveMode $ProcessingMode -ProjectMode $OpenAiProject
    $openAiProjectSummary = if ($ProcessingMode -eq "AI") { $OpenAiProject } else { "" }
    $transcriptionPathDetails = Get-TranscriptionProviderDetails -EffectiveMode $ProcessingMode -ProjectMode $OpenAiProject -Model $OpenAiTranscriptionModel
    $diagnosticsSetting = [Environment]::GetEnvironmentVariable("MM_OPENAI_DIAGNOSTICS")
    if (-not [string]::IsNullOrWhiteSpace($diagnosticsSetting)) {
        $normalizedDiagnosticsSetting = $diagnosticsSetting.Trim()
        if ($normalizedDiagnosticsSetting -notmatch '^(?i)(0|false|no|off)$') {
            if ($normalizedDiagnosticsSetting -match '^(?i)(1|true|yes|on)$') {
                $openAiDiagnosticsFolder = Join-Path $audioOutputRoot "openai_diagnostics"
            }
            elseif ([System.IO.Path]::IsPathRooted($normalizedDiagnosticsSetting)) {
                $openAiDiagnosticsFolder = $normalizedDiagnosticsSetting
            }
            else {
                $openAiDiagnosticsFolder = Join-Path $audioOutputRoot $normalizedDiagnosticsSetting
            }

            Ensure-Directory $openAiDiagnosticsFolder
            Write-Log ("OpenAI segment diagnostics: {0}" -f $openAiDiagnosticsFolder)
        }
    }
    $loggedRequestedProcessingMode = if ([string]::IsNullOrWhiteSpace($RequestedProcessingMode)) {
        $ProcessingMode
    }
    else {
        $RequestedProcessingMode
    }
    $loggedProcessingSelectionSource = if ([string]::IsNullOrWhiteSpace($ProcessingModeSelectionSource)) {
        "default"
    }
    else {
        $ProcessingModeSelectionSource
    }
    Write-Log ("Requested processing mode: {0} ({1})" -f $loggedRequestedProcessingMode, $loggedProcessingSelectionSource)
    if ($ProcessingMode -ne $loggedRequestedProcessingMode) {
        Write-Log ("Effective processing mode request: {0}" -f $processingModeSummary)
    }
    if (-not [string]::IsNullOrWhiteSpace($ProcessingModeResolutionNote)) {
        Write-Log $ProcessingModeResolutionNote "WARN"
    }
    Write-Log ("Resolved processing mode: {0}" -f $processingModeSummary)
    Write-Log ("Transcription path selected: {0}" -f $transcriptionPathDetails)
    if ($ProcessingMode -eq "Local") {
        Write-Log ("Local Whisper model: {0}" -f $ModelName)
    }
    if ($ProcessingMode -eq "AI") {
        Write-Log ("AI project mode: {0}" -f $OpenAiProject)
        if (-not [string]::IsNullOrWhiteSpace($OpenAiTranscriptionModel) -and $OpenAiProject -eq "Private") {
            Write-Log ("OpenAI transcription model: {0}" -f $OpenAiTranscriptionModel)
        }
        if ($TranslationTargets.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($OpenAiModel)) {
            Write-Log ("OpenAI translation model: {0}" -f $OpenAiModel)
        }
    }
    if ($TranslationTargets.Count -gt 0) {
        $loggedRequestedProvider = if ([string]::IsNullOrWhiteSpace($RequestedTranslationProvider)) {
            $TranslationProvider
        }
        else {
            $RequestedTranslationProvider
        }
        $loggedSelectionSource = if ([string]::IsNullOrWhiteSpace($TranslationProviderSelectionSource)) {
            "default"
        }
        else {
            $TranslationProviderSelectionSource
        }

        Write-Log ("Requested translation provider: {0} ({1})" -f $loggedRequestedProvider, $loggedSelectionSource)
        if ($TranslationProvider -ne $loggedRequestedProvider) {
            Write-Log ("Effective translation provider request: {0}" -f $TranslationProvider)
        }
        if (-not [string]::IsNullOrWhiteSpace($TranslationProviderResolutionNote)) {
            Write-Log $TranslationProviderResolutionNote "WARN"
        }
    }

    $preflightResult = Invoke-PhaseAction -Name "Preflight" -Detail $audioItem.Name -Action {
        $phaseHasAudio = Test-VideoHasAudio -FFprobeExe $FFprobeExe -VideoPath $audioItem.FullName
        if (-not $phaseHasAudio) {
            throw "Source file does not contain a readable audio stream."
        }

        $phaseDuration = Get-VideoDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $audioItem.FullName
        Write-Log ("Source duration: {0}" -f (Format-DurationHuman $phaseDuration))

        return [PSCustomObject]@{
            DurationSeconds = $phaseDuration
        }
    }
    $sourceDurationSeconds = [double]$preflightResult.DurationSeconds

    if ($DoCopyRaw) {
        Invoke-PhaseAction -Name "Raw" -Detail $audioItem.Name -Action {
            Ensure-Directory $rawFolder
            if (-not (Test-Path -LiteralPath $rawAudioPath)) {
                Write-Log "Copying raw audio..."
                Copy-Item -LiteralPath $audioItem.FullName -Destination $rawAudioPath -Force
            }
            else {
                Write-Log "Raw audio already copied. Skipping."
            }
        } | Out-Null
    }

    $reviewAudioMode = Invoke-PhaseAction -Name "Audio" -Detail $audioItem.Name -Action {
        Export-ReviewAudioMp3 `
            -FFmpegExe $FFmpegExe `
            -InputMedia $audioItem.FullName `
            -OutputAudio $reviewAudioPath `
            -HeartbeatSeconds $HeartbeatSeconds
    }

    if ($ProcessingMode -eq "Local" -and (Test-LocalWhisperLongCpuRunRisk -ModelName $ModelName -CanUseWhisperGpu $CanUseWhisperGpu -DurationSeconds $sourceDurationSeconds)) {
        Write-LocalWhisperLongCpuRunWarning -ModelName $ModelName -DurationSeconds $sourceDurationSeconds
    }

    $whisperMode = "CPU"
    $transcriptionUsesOpenAi = ($ProcessingMode -eq "AI" -and $OpenAiProject -eq "Private")
    $transcriptResult = Invoke-PhaseAction -Name "Transcript" -Detail $audioItem.Name -Action {
        if ((Test-Path -LiteralPath $originalTranscriptSrt) -and (Test-Path -LiteralPath $originalTranscriptJson) -and (Test-Path -LiteralPath $originalTranscriptText)) {
            Write-Log "Transcript files already exist. Skipping new transcription."
            return [PSCustomObject]@{
                Device   = "existing"
                JsonPath = $originalTranscriptJson
                SrtPath  = $originalTranscriptSrt
                TextPath = $originalTranscriptText
                Language = ""
                GpuError = ""
            }
        }

        if ($transcriptionUsesOpenAi) {
            Write-Log ("Generating transcript with OpenAI transcription ({0})..." -f $OpenAiTranscriptionModel)
            Invoke-OpenAiWhisperTranscript `
                -AudioPath $reviewAudioPath `
                -TranscriptFolder $transcriptFolder `
                -LanguageCode $LanguageCode `
                -Model $OpenAiTranscriptionModel `
                -FFmpegExe $FFmpegExe `
                -FFprobeExe $FFprobeExe `
                -JsonName "transcript_original.json" `
                -SrtName "transcript_original.srt" `
                -TextName "transcript_original.txt" `
                -HeartbeatSeconds $HeartbeatSeconds
        }
        else {
            Write-Log ("Generating transcript with Whisper model '{0}' on {1}..." -f $ModelName, $(if ($CanUseWhisperGpu) { "GPU if available" } else { "CPU" }))
            Invoke-PythonWhisperTranscript `
                -PythonCommand $PythonCommand `
                -AudioPath $reviewAudioPath `
                -TranscriptFolder $transcriptFolder `
                -ModelName $ModelName `
                -LanguageCode $LanguageCode `
                -FFmpegExe $FFmpegExe `
                -PreferGpu $CanUseWhisperGpu `
                -Task "transcribe" `
                -JsonName "transcript_original.json" `
                -SrtName "transcript_original.srt" `
                -TextName "transcript_original.txt" `
                -HeartbeatSeconds $HeartbeatSeconds
        }
    }

    if ($transcriptResult.Device -eq "openai") {
        $whisperMode = "OPENAI"
    }
    elseif ($transcriptResult.Device -eq "cuda") {
        $whisperMode = "GPU_CUDA"
    }
    elseif ($transcriptResult.Device -eq "existing") {
        $whisperMode = "SKIPPED_EXISTING"
    }

    if ($transcriptResult.GpuError) {
        Write-Log "Whisper GPU fallback note: $($transcriptResult.GpuError)" "WARN"
    }

    $transcriptData = Get-TranscriptSegments -TranscriptJsonPath $originalTranscriptJson
    if (-not $transcriptData.Segments -or $transcriptData.Segments.Count -eq 0) {
        throw "Transcript generation completed but no segments were found."
    }

    $detectedLanguage = if (-not [string]::IsNullOrWhiteSpace($transcriptResult.Language)) {
        $transcriptResult.Language
    }
    elseif (-not [string]::IsNullOrWhiteSpace($transcriptData.Language)) {
        $transcriptData.Language
    }
    elseif (-not [string]::IsNullOrWhiteSpace($LanguageCode)) {
        $LanguageCode
    }
    else {
        "unknown"
    }

    Write-Log "Detected source language: $detectedLanguage"

    $normalizedTargets = @($TranslationTargets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $completedTargets = New-Object System.Collections.Generic.List[string]
    $translationProviderDetails = New-Object System.Collections.Generic.List[string]
    $translationRecoveryNotes = New-Object System.Collections.Generic.List[string]
    $translationFailureNotes = New-Object System.Collections.Generic.List[string]
    $translationNextSteps = New-Object System.Collections.Generic.List[string]
    $requestedProvider = [string]$TranslationProvider
    $activeTranslationMode = [string]$TranslationProvider
    $packageStatus = "SUCCESS"
    $shouldFailRun = $false
    $translationStopRequested = $false

    if ($requestedProvider -eq "OpenAI" -and -not (Test-OpenAiTranslationAvailable)) {
        Show-OpenAiSetupGuidance -ProviderLabel "OpenAI translation"
        throw (Get-OpenAiKeyRequirementText)
    }

    foreach ($targetLanguage in $normalizedTargets) {
        if ($translationStopRequested) {
            break
        }

        $phaseDetail = ("{0} -> {1}" -f $audioItem.Name, $targetLanguage)
        Write-Phase -Name "Translation" -Detail $phaseDetail

        $providerUsed = ""
        $translationPhaseCompleted = $false
        $pendingOpenAiFallbackDetails = $null
        $translationFolder = Join-Path $translationsFolder $targetLanguage

        while (-not $translationPhaseCompleted) {
            try {
                $providerPlan = Resolve-TranslationTargetProvider `
                    -TranslationMode $activeTranslationMode `
                    -TargetLanguage $targetLanguage `
                    -DetectedLanguage $detectedLanguage `
                    -ModelName $ModelName `
                    -PythonCommand $PythonCommand `
                    -InteractiveMode:$InteractiveMode `
                    -HeartbeatSeconds $HeartbeatSeconds

                if ($providerPlan.Action -eq "skip") {
                    Write-Log $providerPlan.Note "WARN"
                    $packageStatus = "PARTIAL_SUCCESS"
                    if ($pendingOpenAiFallbackDetails) {
                        [void]$translationFailureNotes.Add(("{0}: {1} Local fallback was skipped. {2}" -f $targetLanguage, $pendingOpenAiFallbackDetails.UserMessage, $providerPlan.Note))
                        [void]$translationNextSteps.Add($pendingOpenAiFallbackDetails.NextStep)
                        $pendingOpenAiFallbackDetails = $null
                    }
                    else {
                        [void]$translationFailureNotes.Add($providerPlan.Note)
                        [void]$translationNextSteps.Add(("Install local translation support or rerun with -ProcessingMode AI for target '{0}'." -f $targetLanguage))
                    }

                    Write-PhaseResult -Name "Translation" -Status "PASS" -Detail ("{0} (skipped)" -f $phaseDetail)
                    $translationPhaseCompleted = $true
                    break
                }

                $providerUsed = $providerPlan.Provider
                Write-Log ("Translation provider for {0}: {1} (mode: {2})" -f $targetLanguage, $providerUsed, $activeTranslationMode)

                Ensure-Directory $translationsFolder
                Ensure-Directory $translationFolder

                if ($providerUsed -eq "Original transcript copy") {
                    Write-Log "Target language matches detected source language. Reusing the original transcript."
                    $null = Write-TranscriptArtifactsFromSegments `
                        -OutputFolder $translationFolder `
                        -Segments $transcriptData.Segments `
                        -Language $detectedLanguage `
                        -SourceLanguage $detectedLanguage `
                        -Task "copy" `
                        -JsonName "transcript.json" `
                        -SrtName "transcript.srt" `
                        -TextName "transcript.txt"
                }
                elseif ($providerUsed -eq "Local (Whisper audio translation)") {
                    $whisperTranslationLanguageCode = if (-not [string]::IsNullOrWhiteSpace($detectedLanguage) -and $detectedLanguage -ne "unknown") {
                        $detectedLanguage
                    }
                    else {
                        $LanguageCode
                    }
                    $whisperTranslationLanguageLabel = if ([string]::IsNullOrWhiteSpace($whisperTranslationLanguageCode)) {
                        "auto-detect"
                    }
                    else {
                        $whisperTranslationLanguageCode
                    }
                    Write-Log ("Running local Whisper audio translation to English with model '{0}' and source language hint '{1}'." -f $ModelName, $whisperTranslationLanguageLabel)
                    $tempJsonName = "transcript_whisper_translate.json"
                    $tempSrtName = "transcript_whisper_translate.srt"
                    $tempTextName = "transcript_whisper_translate.txt"
                    $translateResult = Invoke-PythonWhisperTranscript `
                        -PythonCommand $PythonCommand `
                        -AudioPath $reviewAudioPath `
                        -TranscriptFolder $translationFolder `
                        -ModelName $ModelName `
                        -LanguageCode $whisperTranslationLanguageCode `
                        -FFmpegExe $FFmpegExe `
                        -PreferGpu $CanUseWhisperGpu `
                        -Task "translate" `
                        -JsonName $tempJsonName `
                        -SrtName $tempSrtName `
                        -TextName $tempTextName `
                        -HeartbeatSeconds $HeartbeatSeconds

                    $translatedData = Get-TranscriptSegments -TranscriptJsonPath $translateResult.JsonPath
                    $null = Write-TranscriptArtifactsFromSegments `
                        -OutputFolder $translationFolder `
                        -Segments $translatedData.Segments `
                        -Language "en" `
                        -SourceLanguage $detectedLanguage `
                        -Task "translate" `
                        -JsonName "transcript.json" `
                        -SrtName "transcript.srt" `
                        -TextName "transcript.txt"

                    foreach ($tempPath in @(
                        (Join-Path $translationFolder $tempJsonName),
                        (Join-Path $translationFolder $tempSrtName),
                        (Join-Path $translationFolder $tempTextName)
                    )) {
                        if (Test-Path -LiteralPath $tempPath) {
                            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                elseif ($providerUsed -eq "Local (Argos Translate)") {
                    $translatedSegments = Invoke-ArgosSegmentTranslation `
                        -PythonCommand $PythonCommand `
                        -Segments $transcriptData.Segments `
                        -SourceLanguageCode $detectedLanguage `
                        -TargetLanguageCode $targetLanguage `
                        -HeartbeatSeconds $HeartbeatSeconds

                    $null = Write-TranscriptArtifactsFromSegments `
                        -OutputFolder $translationFolder `
                        -Segments $translatedSegments `
                        -Language $targetLanguage `
                        -SourceLanguage $detectedLanguage `
                        -Task "translate" `
                        -JsonName "transcript.json" `
                        -SrtName "transcript.srt" `
                        -TextName "transcript.txt"
                }
                else {
                    $targetDisplayName = Get-LanguageDisplayName -Code $targetLanguage
                    $sourceDisplayName = Get-LanguageDisplayName -Code $detectedLanguage
                    $translatedSegments = Invoke-OpenAiSegmentTranslation `
                        -Segments $transcriptData.Segments `
                        -SourceLanguage $sourceDisplayName `
                        -TargetLanguage $targetDisplayName `
                        -Model $OpenAiModel `
                        -HeartbeatSeconds $HeartbeatSeconds `
                        -DiagnosticsFolder $openAiDiagnosticsFolder

                    $null = Write-TranscriptArtifactsFromSegments `
                        -OutputFolder $translationFolder `
                        -Segments $translatedSegments `
                        -Language $targetLanguage `
                        -SourceLanguage $detectedLanguage `
                        -Task "translate" `
                        -JsonName "transcript.json" `
                        -SrtName "transcript.srt" `
                        -TextName "transcript.txt"
                }

                [void]$completedTargets.Add($targetLanguage)
                [void]$translationProviderDetails.Add(("{0}={1}" -f $targetLanguage, $providerUsed))
                if ($pendingOpenAiFallbackDetails) {
                    [void]$translationRecoveryNotes.Add(("{0}: {1} Fell back to {2}." -f $targetLanguage, $pendingOpenAiFallbackDetails.UserMessage, $providerUsed))
                    $pendingOpenAiFallbackDetails = $null
                }

                Write-PhaseResult -Name "Translation" -Status "PASS" -Detail $phaseDetail
                $translationPhaseCompleted = $true
            }
            catch {
                $failureDetails = if ($providerUsed -eq "OpenAI") { Get-OpenAiFailureDetails -Exception $_.Exception } else { $null }
                if ($providerUsed -eq "OpenAI" -and $failureDetails -and $failureDetails.Recoverable) {
                    [void]$translationProviderDetails.Add(("{0}={1}" -f $targetLanguage, (Get-OpenAiProviderFailureText -FailureDetails $failureDetails)))
                    if ($activeTranslationMode -eq "Auto") {
                        Write-Log ("OpenAI translation for '{0}' hit a recoverable problem. {1}" -f $targetLanguage, $failureDetails.UserMessage) "WARN"
                        $activeTranslationMode = "Local"
                        $pendingOpenAiFallbackDetails = $failureDetails
                        $providerUsed = ""
                        continue
                    }

                    if ($activeTranslationMode -eq "OpenAI" -and $InteractiveMode) {
                        $canUseLocalFallback = $true
                        $localFallbackNote = ""
                        try {
                            $null = Resolve-TranslationTargetProvider `
                                -TranslationMode "Local" `
                                -TargetLanguage $targetLanguage `
                                -DetectedLanguage $detectedLanguage `
                                -ModelName $ModelName `
                                -PythonCommand $PythonCommand `
                                -InteractiveMode:$InteractiveMode `
                                -HeartbeatSeconds $HeartbeatSeconds
                        }
                        catch {
                            $canUseLocalFallback = $false
                            $localFallbackNote = $_.Exception.Message
                        }

                        $decision = Get-InteractiveOpenAiRuntimeRecoveryDecision `
                            -TargetLanguage $targetLanguage `
                            -FailureDetails $failureDetails `
                            -CanUseLocalFallback:$canUseLocalFallback `
                            -LocalFallbackNote $localFallbackNote
                        if (-not [string]::IsNullOrWhiteSpace($decision.ResolutionNote)) {
                            Write-Log $decision.ResolutionNote "WARN"
                        }

                        if ($decision.Action -eq "Retry") {
                            $providerUsed = ""
                            continue
                        }

                        if ($decision.Action -eq "UseLocal") {
                            $activeTranslationMode = "Local"
                            $pendingOpenAiFallbackDetails = $failureDetails
                            $providerUsed = ""
                            continue
                        }

                        Write-PhaseResult -Name "Translation" -Status "FAIL" -Detail $_.Exception.Message
                        $packageStatus = "PARTIAL_SUCCESS"
                        [void]$translationFailureNotes.Add(("{0}: {1}" -f $targetLanguage, $failureDetails.UserMessage))
                        [void]$translationNextSteps.Add($failureDetails.NextStep)
                        $translationStopRequested = $true
                        $translationPhaseCompleted = $true
                        break
                    }

                    Write-PhaseResult -Name "Translation" -Status "FAIL" -Detail $_.Exception.Message
                    $packageStatus = "PARTIAL_SUCCESS"
                    $shouldFailRun = $true
                    [void]$translationFailureNotes.Add(("{0}: {1}" -f $targetLanguage, $failureDetails.UserMessage))
                    [void]$translationNextSteps.Add($failureDetails.NextStep)
                    $translationStopRequested = $true
                    $translationPhaseCompleted = $true
                    break
                }

                if ($pendingOpenAiFallbackDetails) {
                    Write-PhaseResult -Name "Translation" -Status "FAIL" -Detail $_.Exception.Message
                    $packageStatus = "PARTIAL_SUCCESS"
                    [void]$translationFailureNotes.Add(("{0}: {1} Local fallback could not finish: {2}" -f $targetLanguage, $pendingOpenAiFallbackDetails.UserMessage, $_.Exception.Message))
                    [void]$translationNextSteps.Add($pendingOpenAiFallbackDetails.NextStep)
                    $pendingOpenAiFallbackDetails = $null
                    $translationPhaseCompleted = $true
                    break
                }

                Write-PhaseResult -Name "Translation" -Status "FAIL" -Detail $_.Exception.Message
                throw
            }
        }
    }

    $commentsTextPath = ""
    $commentsJsonPath = ""
    $commentsSummary = ""
    if (-not [string]::IsNullOrWhiteSpace($SourceInfoJsonPath) -and (Test-Path -LiteralPath $SourceInfoJsonPath)) {
        $commentArtifacts = Invoke-PhaseAction -Name "Comments" -Detail $audioItem.Name -Action {
            Export-CommentsArtifactsFromInfoJson -InfoJsonPath $SourceInfoJsonPath -CommentsFolder $commentsFolder
        }

        if ($commentArtifacts) {
            $commentsTextPath = $commentArtifacts.CommentsTextPath
            $commentsJsonPath = $commentArtifacts.CommentsJsonPath
            $commentsSummary = ("{0} public comments exported" -f $commentArtifacts.CommentCount)
            Write-Log $commentsSummary
        }
        else {
            $commentsSummary = "requested, but no public comments were returned by yt-dlp"
            Write-Log $commentsSummary "WARN"
        }
    }

    $segmentCount = Invoke-PhaseAction -Name "Index" -Detail $audioItem.Name -Action {
        Build-SegmentIndex -Segments $transcriptData.Segments -SegmentIndexCsv $segmentIndexCsv
    }

    $rawPresent = if ($DoCopyRaw) { "Yes" } else { "No" }
    $missingTranslationTargets = @($normalizedTargets | Where-Object { $completedTargets -notcontains $_ })
    $translationProviderText = if ($translationProviderDetails.Count -gt 0) {
        ($translationProviderDetails | Select-Object -Unique) -join "; "
    }
    else {
        "none"
    }
    $translationStatusParts = New-Object System.Collections.Generic.List[string]
    if ($normalizedTargets.Count -eq 0) {
        [void]$translationStatusParts.Add("not requested")
    }
    else {
        [void]$translationStatusParts.Add(("completed: {0}" -f $(if ($completedTargets.Count -gt 0) { (@($completedTargets) -join ", ") } else { "none" })))
        if ($missingTranslationTargets.Count -gt 0) {
            [void]$translationStatusParts.Add(("not completed: {0}" -f ($missingTranslationTargets -join ", ")))
        }
    }
    $translationStatusText = $translationStatusParts -join "; "
    $translationNotesParts = @($translationRecoveryNotes) + @($translationFailureNotes)
    $translationNotesText = if ($translationNotesParts.Count -gt 0) {
        ($translationNotesParts | Select-Object -Unique) -join " | "
    }
    else {
        ""
    }
    $nextStepsText = if ($translationNextSteps.Count -gt 0) {
        ($translationNextSteps | Select-Object -Unique) -join " | "
    }
    else {
        ""
    }

    if ($packageStatus -eq "PARTIAL_SUCCESS") {
        Write-Log ("Package marked as partial success. Translation status: {0}" -f $translationStatusText) "WARN"
        if (-not [string]::IsNullOrWhiteSpace($translationProviderText) -and $translationProviderText -ne "none") {
            Write-Log ("Translation path used: {0}" -f $translationProviderText) "WARN"
        }
        if (-not [string]::IsNullOrWhiteSpace($translationNotesText)) {
            Write-Log ("Translation notes: {0}" -f $translationNotesText) "WARN"
        }
        if (-not [string]::IsNullOrWhiteSpace($nextStepsText)) {
            Write-Log ("Next steps: {0}" -f $nextStepsText) "WARN"
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($translationNotesText)) {
        Write-Log ("Translation recovery notes: {0}" -f $translationNotesText) "WARN"
    }

    Invoke-PhaseAction -Name "README" -Detail $audioItem.Name -Action {
        New-CodexReadme `
            -ReadmePath $readmeFile `
            -AudioFileName $audioItem.Name `
            -RawPresent $rawPresent `
            -ProcessingModeSummary $processingModeSummary `
            -OpenAiProjectSummary $openAiProjectSummary `
            -TranscriptionPathDetails $transcriptionPathDetails `
            -DetectedLanguage $detectedLanguage `
            -TranslationTargets @($normalizedTargets) `
            -TranslationPathDetails $translationProviderText `
            -CommentsSummary $commentsSummary `
            -PackageStatus $packageStatus `
            -TranslationStatus $translationStatusText `
            -TranslationNotes $translationNotesText `
            -NextSteps $nextStepsText
    } | Out-Null

    Add-SummaryRow `
        -SummaryCsv $SummaryCsv `
        -SourceAudio $audioItem.Name `
        -OutputFolderName $safeBaseName `
        -OutputPath $audioOutputRoot `
        -AudioFile $reviewAudioPath `
        -OriginalTranscriptSrt $originalTranscriptSrt `
        -OriginalTranscriptJson $originalTranscriptJson `
        -OriginalTranscriptText $originalTranscriptText `
        -SegmentIndexCsv $segmentIndexCsv `
        -RawCopied $rawPresent `
        -DetectedLanguage $detectedLanguage `
        -ProcessingModeSummary $processingModeSummary `
        -OpenAiProjectSummary $openAiProjectSummary `
        -TranscriptionPath $transcriptionPathDetails `
        -TranslationTargets ((@($normalizedTargets)) -join ", ") `
        -TranslationPath $translationProviderText `
        -CommentsText $commentsTextPath `
        -CommentsJson $commentsJsonPath `
        -CommentsSummary $commentsSummary `
        -WhisperMode $whisperMode `
        -PackageStatus $packageStatus `
        -TranslationStatus $translationStatusText `
        -TranslationNotes $translationNotesText `
        -NextSteps $nextStepsText

    return [PSCustomObject]@{
        SourceAudioName     = $audioItem.Name
        OutputFolderName    = $safeBaseName
        OutputPath          = $audioOutputRoot
        ReviewAudioMode     = $reviewAudioMode
        ProcessingMode      = $processingModeSummary
        OpenAiProject       = $openAiProjectSummary
        WhisperMode         = $whisperMode
        TranscriptionPath   = $transcriptionPathDetails
        SegmentCount        = $segmentCount
        DetectedLanguage    = $detectedLanguage
        TranslationTargets  = @($completedTargets)
        TranslationProvider = $translationProviderText
        CommentsSummary     = $commentsSummary
        PackageStatus       = $packageStatus
        TranslationStatus   = $translationStatusText
        TranslationNotes    = $translationNotesText
        NextSteps           = $nextStepsText
        ShouldFailRun       = $shouldFailRun
    }
}

$inputSourceDisplay = if ($remoteInputSources.Count -gt 0) {
    $remoteInputSources -join "; "
}
elseif ($InputPath) {
    $InputPath
}
else {
    $InputFolder
}

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
Ensure-Directory $InputFolder

$doCopyRaw = $CopyRawAudio.IsPresent
if (-not $PSBoundParameters.ContainsKey("CopyRawAudio") -and -not $NoPrompt) {
    $value = Read-Host "Copy original source audio into raw folder? (Y/n)"
    if ([string]::IsNullOrWhiteSpace($value)) {
        $doCopyRaw = $true
    }
    else {
        $doCopyRaw = $value.Trim() -match '^(y|yes)$'
    }
}

$doCreateChatGptZip = $CreateChatGptZip.IsPresent
if (-not $PSBoundParameters.ContainsKey("CreateChatGptZip") -and -not $NoPrompt) {
    $value = Read-Host "Create a ChatGPT upload zip package for each completed audio item? (Y/n)"
    if ([string]::IsNullOrWhiteSpace($value)) {
        $doCreateChatGptZip = $true
    }
    else {
        $doCreateChatGptZip = $value.Trim() -match '^(y|yes)$'
    }
}

$doOpenOutputInExplorer = $OpenOutputInExplorer.IsPresent
if (-not $PSBoundParameters.ContainsKey("OpenOutputInExplorer") -and -not $NoPrompt) {
    $value = Read-Host "Open Windows Explorer to the output folder when finished? (Y/n)"
    if ([string]::IsNullOrWhiteSpace($value)) {
        $doOpenOutputInExplorer = $true
    }
    else {
        $doOpenOutputInExplorer = $value.Trim() -match '^(y|yes)$'
    }
}

$translationTargets = Get-TranslationTargets -Value $TranslateTo
$translationProviderWasExplicit = $PSBoundParameters.ContainsKey("TranslationProvider")
if (-not $PSBoundParameters.ContainsKey("TranslateTo") -and -not $NoPrompt) {
    $translationInput = Read-Host "Translate transcript into additional languages? Enter codes like en, es, fr or press Enter for none"
    $translationTargets = Get-TranslationTargets -Value $translationInput
}

$processingModeWasExplicit = $PSBoundParameters.ContainsKey("ProcessingMode")
$processingModeResolution = Resolve-ProcessingModeRequest `
    -RequestedMode $ProcessingMode `
    -WasExplicitlySet:$processingModeWasExplicit `
    -RequestedLegacyTranslationProvider $TranslationProvider `
    -LegacyProviderWasExplicitlySet:$translationProviderWasExplicit `
    -InteractiveMode:$(-not $NoPrompt)
$ProcessingMode = $processingModeResolution.EffectiveMode

if ($ProcessingMode -eq "AI" -and -not $PSBoundParameters.ContainsKey("OpenAiProject") -and -not $NoPrompt) {
    $OpenAiProject = Get-InteractiveOpenAiProjectMode -DefaultValue "Private"
}
elseif ([string]::IsNullOrWhiteSpace($OpenAiProject)) {
    $OpenAiProject = "Private"
}
else {
    $OpenAiProject = $OpenAiProject.Trim()
}

$openAiProjectResolutionNote = $null
if ($ProcessingMode -ne "AI" -and $PSBoundParameters.ContainsKey("OpenAiProject")) {
    $openAiProjectResolutionNote = ("OpenAiProject {0} was provided, but OpenAiProject only applies in AI mode." -f $OpenAiProject)
}

$whisperModelWasExplicit = $PSBoundParameters.ContainsKey("WhisperModel")
$whisperModelResolutionNote = $null
if (-not [string]::IsNullOrWhiteSpace($WhisperModel)) {
    $WhisperModel = $WhisperModel.Trim()
}
if (-not $whisperModelWasExplicit -and $ProcessingMode -eq "Local") {
    $originalWhisperModel = $WhisperModel
    $WhisperModel = $script:LocalAccuracyWhisperModel
    $whisperModelResolutionNote = ("Local mode defaulted Whisper from '{0}' to '{1}' because local accuracy and nuance are prioritized over speed." -f $originalWhisperModel, $WhisperModel)
}

$TranslationProvider = Get-TranslationModeForProcessingMode -EffectiveMode $ProcessingMode
$requestedLegacyTranslationProvider = if ($translationProviderWasExplicit) { $PSBoundParameters["TranslationProvider"] } else { "" }
$translationProviderResolution = [PSCustomObject]@{
    RequestedProvider = [string]$requestedLegacyTranslationProvider
    EffectiveProvider = $TranslationProvider
    SelectionSource   = if ($translationProviderWasExplicit) { "legacy compatibility flag" } else { "processing mode" }
    ResolutionNote    = if ($translationProviderWasExplicit) {
        "TranslationProvider is a legacy compatibility flag. ProcessingMode is the primary operator-facing control."
    }
    else {
        $null
    }
}

$openAiModelWasExplicit = $PSBoundParameters.ContainsKey("OpenAiModel")
$openAiTranslationModelResolution = $null
if ($ProcessingMode -eq "AI") {
    if ($translationTargets.Count -gt 0) {
        $openAiTranslationModelResolution = Resolve-OpenAiApprovedModelSelection `
            -Capability "Translation" `
            -ProjectMode $OpenAiProject `
            -RequestedModel $OpenAiModel `
            -WasExplicitlySet:$openAiModelWasExplicit
        $OpenAiModel = $openAiTranslationModelResolution.ResolvedModel
    }
    elseif ($openAiModelWasExplicit -and -not [string]::IsNullOrWhiteSpace($OpenAiModel)) {
        $OpenAiModel = $OpenAiModel.Trim()
    }
    else {
        $OpenAiModel = Get-OpenAiApprovedModelFallbackDefault -Capability "Translation" -ProjectMode $OpenAiProject
    }
}
elseif (-not $openAiModelWasExplicit -or [string]::IsNullOrWhiteSpace($OpenAiModel)) {
    $OpenAiModel = $script:OpenAiPrivateTranslationDefaultModel
}

$ResolvedOpenAiTranscriptionModel = $script:OpenAiTranscriptionModel
$processingModeSummary = Get-ProcessingModeSummary -EffectiveMode $ProcessingMode -ProjectMode $OpenAiProject
$transcriptionPathSummary = Get-TranscriptionProviderDetails -EffectiveMode $ProcessingMode -ProjectMode $OpenAiProject -Model $ResolvedOpenAiTranscriptionModel
$translationModeSummary = Get-TranslationModeSummary `
    -EffectiveMode $ProcessingMode `
    -ProjectMode $OpenAiProject `
    -Model $OpenAiModel `
    -TranslationRequested:($translationTargets.Count -gt 0)

if (($ProcessingMode -eq "Local" -or ($ProcessingMode -eq "AI" -and $OpenAiProject -eq "Public")) -and $translationTargets.Count -gt 0 -and $whisperModelWasExplicit -and -not (Test-WhisperModelSupportsTranslation -ModelName $WhisperModel)) {
    throw "Translation needs a multilingual Whisper model. The selected model '$WhisperModel' is English-only. Use 'large' or another supported Whisper model that does not end in '.en'."
}

$translationProviderPreflightNotes = @()
if ($translationTargets.Count -gt 0) {
    $translationProviderPreflightNotes = @(Get-TranslationProviderPreflightNotes `
            -EffectiveProvider $TranslationProvider `
            -TranslationTargets $translationTargets `
            -ModelName $WhisperModel `
            -PythonCommand $PythonExe `
            -InteractiveMode:$(-not $NoPrompt) `
            -HeartbeatSeconds $HeartbeatSeconds)
}

$bootstrapLog = Join-Path $OutputFolder "_script_bootstrap.log"
$script:CurrentLogFile = $bootstrapLog
"==== Bootstrap started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====" | Set-Content -Path $bootstrapLog -Encoding UTF8
Write-Log "Output folder root: $OutputFolder"
Write-Log ("Requested processing mode: {0} ({1})" -f $(if ([string]::IsNullOrWhiteSpace($processingModeResolution.RequestedMode)) { $ProcessingMode } else { $processingModeResolution.RequestedMode }), $processingModeResolution.SelectionSource)
if ($ProcessingMode -ne $processingModeResolution.RequestedMode -and -not [string]::IsNullOrWhiteSpace($processingModeResolution.RequestedMode)) {
    Write-Log ("Effective processing mode request: {0}" -f $processingModeSummary)
}
if (-not [string]::IsNullOrWhiteSpace($processingModeResolution.ResolutionNote)) {
    Write-Log $processingModeResolution.ResolutionNote "WARN"
}
if (-not [string]::IsNullOrWhiteSpace($openAiProjectResolutionNote)) {
    Write-Log $openAiProjectResolutionNote "WARN"
}
if (-not [string]::IsNullOrWhiteSpace($whisperModelResolutionNote)) {
    Write-Log $whisperModelResolutionNote
}
Write-Log ("Resolved processing mode: {0}" -f $processingModeSummary)
Write-Log ("Transcription path selected: {0}" -f $transcriptionPathSummary)
if ($ProcessingMode -eq "Local") {
    Write-Log ("Local Whisper model: {0}" -f $WhisperModel)
}
if ($ProcessingMode -eq "AI") {
    Write-Log ("AI project mode: {0}" -f $OpenAiProject)
    if ($translationTargets.Count -gt 0) {
        if ($openAiTranslationModelResolution -and -not [string]::IsNullOrWhiteSpace($openAiTranslationModelResolution.ResolutionNote)) {
            Write-Log $openAiTranslationModelResolution.ResolutionNote
        }
        Write-Log ("OpenAI translation model: {0}" -f $OpenAiModel)
    }
}
if ($translationTargets.Count -gt 0) {
    Write-Log ("Translation targets selected: {0}" -f ($translationTargets -join ", "))
    Write-Log ("Translation path selected: {0}" -f $translationModeSummary)
    if (-not [string]::IsNullOrWhiteSpace($translationProviderResolution.RequestedProvider)) {
        Write-Log ("Requested legacy TranslationProvider: {0} ({1})" -f $translationProviderResolution.RequestedProvider, $translationProviderResolution.SelectionSource)
        Write-Log ("Effective translation provider request: {0}" -f $TranslationProvider)
    }
    if (-not [string]::IsNullOrWhiteSpace($translationProviderResolution.ResolutionNote)) {
        Write-Log $translationProviderResolution.ResolutionNote "WARN"
    }
    foreach ($preflightNote in $translationProviderPreflightNotes) {
        Write-Log $preflightNote "WARN"
    }
}

$masterReadme = Join-Path $OutputFolder "CODEX_MASTER_README.txt"
$summaryCsv = Join-Path $OutputFolder "PROCESSING_SUMMARY.csv"
$downloadedInputPaths = @()
$downloadedInputCount = 0
$downloadedInputKinds = @()
$sourceInfoJsonByAudioPath = @{}
try {
    $audioItems = @()
    $ytDlpInvoker = $null
    try {
        $ytDlpInvoker = Resolve-YtDlpInvoker -PreferredCommand $YtDlpPath -PythonCommand $PythonExe
    }
    catch {
        Write-Log ("yt-dlp is not currently available: {0}" -f $_.Exception.Message) "WARN"
    }

    if ($remoteInputSources.Count -gt 0) {
        $downloadCacheFolder = $InputFolder
        $doIncludeComments = $IncludeComments.IsPresent
        if (-not $PSBoundParameters.ContainsKey("IncludeComments") -and -not $NoPrompt) {
            $value = Read-Host "If comments are available for a YouTube source, save them in the package too? (Y/n):"
            if ([string]::IsNullOrWhiteSpace($value)) {
                $doIncludeComments = $true
            }
            else {
                $doIncludeComments = $value.Trim() -match '^(?i)(y|yes)$'
            }
        }
        if ($ytDlpInvoker) {
            Write-Log "Downloading remote input with $($ytDlpInvoker.DisplayName)"
        }
        else {
            Write-Log "Downloading remote input without yt-dlp where direct audio/page fallback is possible."
        }

        foreach ($remoteSource in $remoteInputSources) {
            $downloadResult = Invoke-PhaseAction -Name "Download" -Detail $remoteSource -Action {
                Invoke-RemoteAudioDownload `
                    -SourceUrl $remoteSource `
                    -DownloadFolder $downloadCacheFolder `
                    -YtDlpInvoker $ytDlpInvoker `
                    -IncludeComments:$doIncludeComments `
                    -HeartbeatSeconds $HeartbeatSeconds
            }

            $downloadedInputPaths += $downloadResult.DownloadRoot
            $downloadedInputKinds += $downloadResult.SourceKind
            $downloadedInputCount += @($downloadResult.DownloadedPaths).Count
            $infoJsonMap = @{}
            if ($null -ne $downloadResult.PSObject.Properties['InfoJsonByMediaPath'] -and $downloadResult.InfoJsonByMediaPath) {
                $infoJsonMap = $downloadResult.InfoJsonByMediaPath
            }
            foreach ($downloadedPath in @($downloadResult.DownloadedPaths)) {
                if ($infoJsonMap.ContainsKey($downloadedPath)) {
                    $sourceInfoJsonByAudioPath[$downloadedPath] = $infoJsonMap[$downloadedPath]
                }
            }
            $audioItems += @($downloadResult.DownloadedPaths | ForEach-Object { Get-Item -LiteralPath $_ })
        }
    }
    elseif ($InputPath) {
        $audioItems = Get-AudioFilesFromPath -Path $InputPath
    }
    else {
        $audioItems = Get-AudioFilesFromPath -Path $InputFolder

        if ((-not $audioItems -or $audioItems.Count -eq 0) -and -not $NoPrompt) {
            Write-Host "No supported audio files found in the selected local input source." -ForegroundColor Yellow
            $manual = Get-InteractiveInputSource `
                -DefaultInputFolder $InputFolder `
                -YtDlpCommand $YtDlpPath `
                -PythonCommand $PythonExe

            $manualRemoteSources = @()
            if ($manual -is [System.Array]) {
                $manualRemoteSources = @($manual)
            }
            elseif (Test-IsHttpUrl -Value $manual) {
                $manualRemoteSources = @([string]$manual)
            }

            if ($manualRemoteSources.Count -gt 0) {
                $downloadCacheFolder = $InputFolder
                $doIncludeComments = $IncludeComments.IsPresent
                if (-not $PSBoundParameters.ContainsKey("IncludeComments") -and -not $NoPrompt) {
                    $value = Read-Host "If comments are available for a YouTube source, save them in the package too? (Y/n):"
                    if ([string]::IsNullOrWhiteSpace($value)) {
                        $doIncludeComments = $true
                    }
                    else {
                        $doIncludeComments = $value.Trim() -match '^(?i)(y|yes)$'
                    }
                }
                if ($ytDlpInvoker) {
                    Write-Log "Downloading remote input with $($ytDlpInvoker.DisplayName)"
                }
                else {
                    Write-Log "Downloading remote input without yt-dlp where direct audio/page fallback is possible."
                }

                $downloadedInputPaths = @()
                $downloadedInputKinds = @()
                $downloadedInputCount = 0
                $audioItems = @()

                foreach ($manualRemoteSource in $manualRemoteSources) {
                    $downloadResult = Invoke-PhaseAction -Name "Download" -Detail $manualRemoteSource -Action {
                        Invoke-RemoteAudioDownload `
                            -SourceUrl $manualRemoteSource `
                            -DownloadFolder $downloadCacheFolder `
                            -YtDlpInvoker $ytDlpInvoker `
                            -IncludeComments:$doIncludeComments `
                            -HeartbeatSeconds $HeartbeatSeconds
                    }

                    $downloadedInputPaths += $downloadResult.DownloadRoot
                    $downloadedInputKinds += $downloadResult.SourceKind
                    $downloadedInputCount += @($downloadResult.DownloadedPaths).Count
                    $infoJsonMap = @{}
                    if ($null -ne $downloadResult.PSObject.Properties['InfoJsonByMediaPath'] -and $downloadResult.InfoJsonByMediaPath) {
                        $infoJsonMap = $downloadResult.InfoJsonByMediaPath
                    }
                    foreach ($downloadedPath in @($downloadResult.DownloadedPaths)) {
                        if ($infoJsonMap.ContainsKey($downloadedPath)) {
                            $sourceInfoJsonByAudioPath[$downloadedPath] = $infoJsonMap[$downloadedPath]
                        }
                    }
                    $audioItems += @($downloadResult.DownloadedPaths | ForEach-Object { Get-Item -LiteralPath $_ })
                }

                $inputSourceDisplay = $manualRemoteSources -join "; "
            }
            else {
                $inputSourceDisplay = $manual
                $audioItems = Get-AudioFilesFromPath -Path $manual
            }
        }
    }

    if (-not $audioItems -or $audioItems.Count -eq 0) {
        throw "No supported audio files found to process."
    }

    $audioItems = @($audioItems | Sort-Object FullName -Unique)

    if (Test-Path -LiteralPath $summaryCsv) {
        Remove-Item -LiteralPath $summaryCsv -Force
    }

    foreach ($audioItem in $audioItems) {
        try {
            if (-not (Test-VideoHasAudio -FFprobeExe $FFprobePath -VideoPath $audioItem.FullName)) {
                throw "No readable audio stream found in $($audioItem.FullName)"
            }
        }
        catch {
            Write-Log "Audio probe warning for $($audioItem.FullName): $($_.Exception.Message)" "WARN"
        }
    }

    if ($ProcessingMode -eq "AI" -and $OpenAiProject -eq "Private" -and $audioItems.Count -gt 0) {
        $openAiTranscriptionModelResolution = Resolve-OpenAiApprovedModelSelection `
            -Capability "Transcription" `
            -ProjectMode $OpenAiProject `
            -RequestedModel $script:OpenAiTranscriptionModel
        $ResolvedOpenAiTranscriptionModel = $openAiTranscriptionModelResolution.ResolvedModel
        $transcriptionPathSummary = Get-TranscriptionProviderDetails -EffectiveMode $ProcessingMode -ProjectMode $OpenAiProject -Model $ResolvedOpenAiTranscriptionModel
        if ($openAiTranscriptionModelResolution -and -not [string]::IsNullOrWhiteSpace($openAiTranscriptionModelResolution.ResolutionNote)) {
            Write-Log $openAiTranscriptionModelResolution.ResolutionNote
        }
    }

    if ($ProcessingMode -eq "AI" -and (($OpenAiProject -eq "Private" -and $audioItems.Count -gt 0) -or $translationTargets.Count -gt 0)) {
        $requiredOpenAiLabel = if ($OpenAiProject -eq "Private" -and $audioItems.Count -gt 0) {
            "AI mode"
        }
        else {
            "OpenAI translation"
        }
        $null = Get-OpenAiApiKey -Required -ProviderLabel $requiredOpenAiLabel
    }

    $requiresLocalWhisper = ($ProcessingMode -ne "AI" -or $OpenAiProject -eq "Public")
    if ($audioItems.Count -gt 0 -and $requiresLocalWhisper) {
        Test-PythonWhisper -PythonCommand $PythonExe
    }

    $nvidiaPresent = Test-NvidiaSmiAvailable
    $whisperProbe = Get-WhisperExecutionMode -PythonCommand $PythonExe

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
    Write-Host ("yt-dlp:   {0}" -f $(if ($ytDlpInvoker) { $ytDlpInvoker.DisplayName } else { "not resolved" }))
    Write-Host ""
    Write-Host "Hardware Acceleration Detection"
    Write-Host "-------------------------------"
    Write-Host ("NVIDIA GPU detected (nvidia-smi): {0}" -f $(if ($nvidiaPresent) { "Yes" } else { "No" }))
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
    Write-Host ("Local Whisper path:             {0}" -f $(if ($requiresLocalWhisper) { $(if ($canUseWhisperGpu) { "GPU preferred with CPU fallback" } else { "CPU fallback" }) } else { "not used in AI Private mode" }))
    Write-Host ("Heartbeat interval:              {0} seconds" -f $HeartbeatSeconds)
    Write-Host ("Input source:                    {0}" -f $inputSourceDisplay)
    if ($downloadedInputPaths.Count -gt 0) {
        Write-Host ("Downloaded input cache:          {0}" -f ($downloadedInputPaths -join "; "))
        Write-Host ("Downloaded source type:          {0}" -f ($downloadedInputKinds -join ", "))
        Write-Host ("Downloaded audio count:          {0}" -f $downloadedInputCount)
    }
    Write-Host ("Output folder:                   {0}" -f $OutputFolder)
    Write-Host ("Processing mode:                 {0}" -f $processingModeSummary)
    if ($ProcessingMode -eq "Local") {
        Write-Host ("Local Whisper model:            {0}" -f $WhisperModel)
    }
    if ($ProcessingMode -eq "AI") {
        Write-Host ("AI project mode:                 {0}" -f $OpenAiProject)
        if ($OpenAiProject -eq "Private" -and $audioItems.Count -gt 0) {
            Write-Host ("OpenAI transcription model:      {0}" -f $ResolvedOpenAiTranscriptionModel)
        }
        if ($translationTargets.Count -gt 0) {
            Write-Host ("OpenAI translation model:        {0}" -f $OpenAiModel)
        }
    }
    Write-Host ("Transcription path selected:     {0}" -f $transcriptionPathSummary)
    Write-Host ("Translation targets:             {0}" -f $(if ($translationTargets.Count -gt 0) { $translationTargets -join ", " } else { "none" }))
    Write-Host ("Translation path selected:       {0}" -f $translationModeSummary)
    Write-Host ("Comments export:                 {0}" -f $(if ($IncludeComments.IsPresent -or $doIncludeComments) { "requested when available" } else { "off" }))
    Write-Host ""
    Write-Host "Audio items to process:"
    $audioItems | ForEach-Object { Write-Host " - $($_.FullName)" }
    Write-Host ""

    $estimate = $null
    if (-not $SkipEstimate) {
        $estimate = Get-BestEffortAudioEstimate `
            -AudioItems $audioItems `
            -FFmpegExe $FFmpegPath `
            -FFprobeExe $FFprobePath `
            -CanUseWhisperGpu $canUseWhisperGpu `
            -TranslationTargets $translationTargets
    }
    else {
        Write-Log "Skipping runtime estimate because -SkipEstimate was requested." "WARN"
    }

    if ($estimate) {
        Write-Host "Estimated completion for this run"
        Write-Host "---------------------------------"
        Write-Host ("Total media duration:   {0}" -f (Format-DurationHuman $estimate.TotalDurationSeconds))
        Write-Host ("Review audio build:     {0}" -f (Format-DurationHuman $estimate.AudioEstimateSeconds))
        Write-Host ("Whisper transcription:  {0}" -f (Format-DurationHuman $estimate.WhisperEstimateSeconds))
        Write-Host ("Translations:           {0}" -f (Format-DurationHuman $estimate.TranslationEstimateSeconds))
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
    $chatGptPackages = @()

    foreach ($audioItem in $audioItems) {
        try {
            $result = Process-Audio `
                -AudioPath $audioItem.FullName `
                -BaseOutputFolder $OutputFolder `
                -FFmpegExe $FFmpegPath `
                -FFprobeExe $FFprobePath `
                -PythonCommand $PythonExe `
                -ModelName $WhisperModel `
                -LanguageCode $Language `
                -TranslationTargets $translationTargets `
                -SourceInfoJsonPath $(if ($sourceInfoJsonByAudioPath.ContainsKey($audioItem.FullName)) { $sourceInfoJsonByAudioPath[$audioItem.FullName] } else { "" }) `
                -DoCopyRaw:$doCopyRaw `
                -SummaryCsv $summaryCsv `
                -CanUseWhisperGpu $canUseWhisperGpu `
                -InteractiveMode:$(-not $NoPrompt) `
                -RequestedProcessingMode $processingModeResolution.RequestedMode `
                -ProcessingModeSelectionSource $processingModeResolution.SelectionSource `
                -ProcessingModeResolutionNote $processingModeResolution.ResolutionNote `
                -ProcessingMode $ProcessingMode `
                -OpenAiProject $OpenAiProject `
                -RequestedTranslationProvider $translationProviderResolution.RequestedProvider `
                -TranslationProviderSelectionSource $translationProviderResolution.SelectionSource `
                -TranslationProviderResolutionNote $translationProviderResolution.ResolutionNote `
                -TranslationProvider $TranslationProvider `
                -OpenAiModel $OpenAiModel `
                -OpenAiTranscriptionModel $ResolvedOpenAiTranscriptionModel `
                -HeartbeatSeconds $HeartbeatSeconds

            $processedItems += $result

            if ($doCreateChatGptZip) {
                $zipInfo = Invoke-PhaseAction -Name "ChatGPT zip" -Detail $result.SourceAudioName -Action {
                    New-ChatGptZipPackage -ProcessedItem $result -MaxSizeMb $ChatGptZipMaxMb
                }
                $chatGptPackages += [PSCustomObject]@{
                    SourceAudioName = $result.SourceAudioName
                    ZipPath         = $zipInfo.ZipPath
                    ZipSizeMb       = $zipInfo.ZipSizeMb
                    AudioIncluded   = $zipInfo.AudioIncluded
                }
            }
        }
        catch {
            $failedItems += [PSCustomObject]@{
                AudioPath = $audioItem.FullName
                Message   = $_.Exception.Message
            }

            Write-Host ""
            Write-Host ("FAIL {0}" -f $audioItem.FullName) -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red

            if ($script:CurrentLogFile) {
                Add-Content -LiteralPath $script:CurrentLogFile -Value "----- FAILURE -----"
                Add-Content -LiteralPath $script:CurrentLogFile -Value $_.Exception.Message
                if ($_.ScriptStackTrace) {
                    Add-Content -LiteralPath $script:CurrentLogFile -Value $_.ScriptStackTrace
                }
            }
        }
    }

    New-MasterReadme -MasterReadmePath $masterReadme -OutputRoot $OutputFolder -ProcessedItems $processedItems

    Write-Phase -Name "Final Summary" -Detail "Packaging complete"
    $partialItems = @($processedItems | Where-Object { $_.PackageStatus -eq "PARTIAL_SUCCESS" })
    $blockingPartialItems = @($processedItems | Where-Object { $_.ShouldFailRun })
    Write-Host ("Successful packages: {0}" -f ($processedItems.Count - $partialItems.Count))
    Write-Host ("Partial packages:    {0}" -f $partialItems.Count)
    Write-Host ("Failed packages:     {0}" -f $failedItems.Count)
    Write-Host ("Output root:         {0}" -f $OutputFolder)
    Write-Host ("Master README:       {0}" -f $masterReadme)
    Write-Host ("Processing summary:  {0}" -f $summaryCsv)

    foreach ($item in $processedItems) {
        if ($item.PackageStatus -eq "PARTIAL_SUCCESS") {
            Write-Host ("PARTIAL {0}" -f $item.SourceAudioName) -ForegroundColor Yellow
        }
        else {
            Write-Host ("PASS {0}" -f $item.SourceAudioName) -ForegroundColor Green
        }
        Write-Host ("  Output:  {0}" -f $item.OutputPath)
        Write-Host ("  Mode:    {0}" -f $item.ProcessingMode)
        if (-not [string]::IsNullOrWhiteSpace($item.OpenAiProject)) {
            Write-Host ("  AI:      {0}" -f $item.OpenAiProject)
        }
        Write-Host ("  Review:  {0}" -f $item.ReviewAudioMode)
        Write-Host ("  Trans:   {0}" -f $item.TranscriptionPath)
        Write-Host ("  Engine:  {0}" -f $item.WhisperMode)
        Write-Host ("  Lang:    {0}" -f $item.DetectedLanguage)
        Write-Host ("  Xlate:   {0}" -f $(if ($item.TranslationTargets.Count -gt 0) { $item.TranslationTargets -join ", " } else { "none" }))
        Write-Host ("  Path:    {0}" -f $(if ([string]::IsNullOrWhiteSpace($item.TranslationProvider) -or $item.TranslationProvider -eq "none") { "none" } else { $item.TranslationProvider }))
        if (-not [string]::IsNullOrWhiteSpace($item.TranslationStatus)) {
            Write-Host ("  Status:  {0}" -f $item.TranslationStatus)
        }
        if (-not [string]::IsNullOrWhiteSpace($item.TranslationNotes)) {
            Write-Host ("  Notes:   {0}" -f $item.TranslationNotes)
        }
        if (-not [string]::IsNullOrWhiteSpace($item.NextSteps)) {
            Write-Host ("  Next:    {0}" -f $item.NextSteps)
        }
        if (-not [string]::IsNullOrWhiteSpace($item.CommentsSummary)) {
            Write-Host ("  Comments:{0}" -f " $($item.CommentsSummary)")
        }
    }

    foreach ($zip in $chatGptPackages) {
        Write-Host ("ChatGPT ZIP {0}" -f $zip.SourceAudioName) -ForegroundColor Cyan
        Write-Host ("  File:   {0}" -f $zip.ZipPath)
        Write-Host ("  SizeMB: {0}" -f $zip.ZipSizeMb)
        Write-Host ("  Audio:  {0}" -f $(if ($zip.AudioIncluded) { "included" } else { "omitted to stay under limit" }))
    }

    foreach ($item in $failedItems) {
        Write-Host ("FAIL {0}" -f $item.AudioPath) -ForegroundColor Red
        Write-Host ("  Error: {0}" -f $item.Message) -ForegroundColor Red
    }

    if ($failedItems.Count -gt 0 -or $blockingPartialItems.Count -gt 0 -or $processedItems.Count -eq 0) {
        Write-Log ("FAIL: Processing completed with {0} hard failure(s) and {1} partial package(s) requiring attention." -f $failedItems.Count, $blockingPartialItems.Count) "ERROR"
        throw ("Processing completed with {0} hard failure(s) and {1} partial package(s) requiring attention." -f $failedItems.Count, $blockingPartialItems.Count)
    }

    Write-Log ("PASS: Processed {0} audio item(s). Partial packages: {1}. Output root: {2}" -f $processedItems.Count, $partialItems.Count, $OutputFolder)
}
finally {
    if (-not $KeepTempFiles) {
        foreach ($downloadPath in @($downloadedInputPaths | Select-Object -Unique)) {
            if (-not [string]::IsNullOrWhiteSpace($downloadPath) -and (Test-Path -LiteralPath $downloadPath)) {
                Remove-Item -LiteralPath $downloadPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path -LiteralPath $bootstrapLog) {
            Remove-Item -LiteralPath $bootstrapLog -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($doOpenOutputInExplorer) {
    try {
        Invoke-Item -LiteralPath $OutputFolder
        Write-Log "Opened output folder in Windows Explorer."
    }
    catch {
        Write-Log "Could not open output folder in Windows Explorer: $($_.Exception.Message)" "WARN"
    }
}
