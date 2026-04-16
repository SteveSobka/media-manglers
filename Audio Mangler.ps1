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
    [ValidateSet("Auto", "OpenAI", "Local")]
    [string]$TranslationProvider = "Auto",
    [string]$OpenAiModel = "gpt-5-mini",
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
$script:FallbackAppVersion = "0.5.0"
$script:SessionOpenAiApiKey = $null

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
        [string]$DetectedLanguage,
        [string[]]$TranslationTargets,
        [string]$TranslationProviderDetails,
        [string]$CommentsSummary
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
- script_run.log                  processing log

A good review order:
1. Start with transcript\transcript_original.txt for the quick read.
2. Use transcript\transcript_original.srt or segment_index.csv when you need timestamps.
3. Open translations\<lang>\ only if you asked for translated text.
4. Use audio\review_audio.mp3 when tone, pronunciation, or emphasis matters.
5. Check comments\ if public source comments were included for extra context.

Notes:
- Detected source language: $DetectedLanguage
- Translation targets: $(if ($TranslationTargets -and $TranslationTargets.Count -gt 0) { $TranslationTargets -join ", " } else { "none" })
- Translation path used: $(if ([string]::IsNullOrWhiteSpace($TranslationProviderDetails)) { "none" } else { $TranslationProviderDetails })
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
    $lines += "- script_run.log"
    $lines += ""
    $lines += "Processed packages:"
    foreach ($item in $ProcessedItems) {
        $lines += "- $($item.OutputFolderName)  <=  $($item.SourceAudioName)"
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
        [string]$TranslationTargets,
        [string]$TranslationProvider,
        [string]$CommentsText,
        [string]$CommentsJson,
        [string]$CommentsSummary,
        [string]$WhisperMode
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
        translation_targets      = $TranslationTargets
        translation_provider     = $TranslationProvider
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
        Write-Host "  2. OpenAI highest quality, uses the OpenAI API and needs OPENAI_API_KEY" -ForegroundColor Cyan
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

function Get-OpenAiSetupInstructionsText {
    param(
        [string]$ProviderLabel = "OpenAI translation"
    )

    $lines = @(
        ("{0} was selected, but OPENAI_API_KEY is not available." -f $ProviderLabel),
        ("OPENAI_API_KEY lets {0} send transcript text to the OpenAI API for translation." -f $script:AppName),
        "Create the key in your OpenAI Platform account on https://platform.openai.com/api-keys.",
        "OpenAI API usage may incur charges.",
        "For normal local desktop use, create a user-owned key.",
        "If project scoping is available, put Media Manglers in a dedicated project.",
        "Prefer Restricted permissions when the UI clearly shows the API access you need. Read Only is not enough.",
        "Service accounts are better for shared automation, servers, or CI than normal personal desktop use.",
        "If the permission UI is unclear, safest fallback is a user-owned key inside a dedicated project.",
        "Current PowerShell session:",
        '  $env:OPENAI_API_KEY="sk-..."',
        "Persistent Windows user variable:",
        '  [System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY","sk-...","User")',
        "After setting the user variable, open a new PowerShell window and rerun with -TranslationProvider OpenAI.",
        "Do not hardcode the key in the script or commit it to GitHub.",
        "If you do not want to use OpenAI, rerun with -TranslationProvider Auto or Local."
    )

    return ($lines -join "`n")
}

function Read-OpenAiApiKeyForCurrentRun {
    if ([System.Console]::IsInputRedirected) {
        $rawValue = Read-Host "Paste OPENAI_API_KEY for this run only"
        return [string]$rawValue
    }

    $secureValue = Read-Host "Paste OPENAI_API_KEY for this run only" -AsSecureString
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
            Write-Host "OpenAI translation was selected." -ForegroundColor Yellow
            Write-Host "Create the key in your OpenAI Platform account. This app sends transcript text to the OpenAI API for translation." -ForegroundColor Yellow
            Write-Host "OpenAI API usage may incur charges." -ForegroundColor Yellow
            Write-Host "For normal local desktop use, a user-owned key is recommended. Service accounts are better for servers, CI, or shared automation." -ForegroundColor Yellow
            Write-Host "If project scoping is available, use a dedicated project. Prefer Restricted when the needed API access is clear. Read Only is not enough." -ForegroundColor Yellow
            Write-Host 'PowerShell now: $env:OPENAI_API_KEY="sk-..."' -ForegroundColor DarkYellow
            Write-Host '[System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY","sk-...","User")' -ForegroundColor DarkYellow
            Write-Host "If you set the user variable, open a new PowerShell window before re-checking." -ForegroundColor Yellow
            $showSetupGuidance = $false
        }
        Write-Host "Choose how to continue:" -ForegroundColor Yellow
        Write-Host "  1. Paste an API key for this run only" -ForegroundColor Cyan
        Write-Host "  2. Re-check after setting OPENAI_API_KEY externally" -ForegroundColor Cyan
        Write-Host "  3. Switch to Auto" -ForegroundColor Cyan
        Write-Host "  4. Switch to Local" -ForegroundColor Cyan
        Write-Host "  5. Cancel" -ForegroundColor Cyan

        $choice = Read-Host "Type 1, 2, 3, 4, or 5"
        switch ($choice.Trim()) {
            "1" {
                $pastedKey = [string](Read-OpenAiApiKeyForCurrentRun)
                if ([string]::IsNullOrWhiteSpace($pastedKey)) {
                    Write-Host "No API key was pasted. Choose another option or try again." -ForegroundColor Yellow
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
                        ResolutionNote    = "OpenAI translation was selected. OPENAI_API_KEY was found after re-check."
                    }
                }

                Write-Host "OPENAI_API_KEY still was not found. Set it in another window or choose a different option." -ForegroundColor Yellow
            }
            "3" {
                return [PSCustomObject]@{
                    EffectiveProvider = "Auto"
                    ResolutionNote    = "OpenAI translation was selected, but OPENAI_API_KEY is missing. Interactive recovery selected: Auto."
                }
            }
            "4" {
                return [PSCustomObject]@{
                    EffectiveProvider = "Local"
                    ResolutionNote    = "OpenAI translation was selected, but OPENAI_API_KEY is missing. Interactive recovery selected: Local."
                }
            }
            "5" {
                throw "OpenAI translation was selected, but OPENAI_API_KEY is still not available. Translation was canceled at the provider preflight prompt."
            }
            default {
                Write-Host "Please type 1, 2, 3, 4, or 5." -ForegroundColor Yellow
            }
        }
    }
}

function Get-OpenAiApiKey {
    param([switch]$Required)

    $apiKey = [string]$script:SessionOpenAiApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        foreach ($scope in @(
                [System.EnvironmentVariableTarget]::Process,
                [System.EnvironmentVariableTarget]::User,
                [System.EnvironmentVariableTarget]::Machine)) {
            $candidate = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", $scope)
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $apiKey = $candidate
                break
            }
        }
    }

    if ($Required -and [string]::IsNullOrWhiteSpace($apiKey)) {
        throw (Get-OpenAiSetupInstructionsText -ProviderLabel "OpenAI translation")
    }

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        return $null
    }

    return $apiKey.Trim()
}

function Test-OpenAiTranslationAvailable {
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
            $resolutionNote = "OpenAI was present without an explicit user override, but OPENAI_API_KEY is missing. Falling back to Auto."
        }
        elseif ($InteractiveMode) {
            $recoveryDecision = Get-InteractiveOpenAiRecoveryDecision
            $effectiveProvider = $recoveryDecision.EffectiveProvider
            $resolutionNote = $recoveryDecision.ResolutionNote
        }
        else {
            throw (Get-OpenAiSetupInstructionsText -ProviderLabel "OpenAI translation")
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
        throw ("Local translation to English needs a multilingual Whisper model. The selected model '{0}' is English-only. Use a model like 'base' or 'small', or rerun with -TranslationProvider Auto or OpenAI." -f $ModelName)
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
        "You can also rerun with -TranslationProvider Auto or OpenAI."
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
        throw "Local translation needs a known source language code. Try -TranslationProvider OpenAI, or rerun with -Language if you know the source language."
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

function Invoke-OpenAiSegmentTranslation {
    param(
        [array]$Segments,
        [string]$SourceLanguage,
        [string]$TargetLanguage,
        [string]$Model,
        [int]$HeartbeatSeconds = 10
    )

    $apiKey = Get-OpenAiApiKey -Required
    $headers = @{
        Authorization = "Bearer $apiKey"
        "Content-Type" = "application/json"
    }

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
            $response = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/chat/completions" -Headers $headers -Body $body
        }
        catch {
            throw "OpenAI translation failed for language '$TargetLanguage'. $($_.Exception.Message)"
        }

        $translatedText = [string]$response.choices[0].message.content
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
    with open(input_path, "r", encoding="utf-8") as f:
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

    $payload = Get-Content -LiteralPath $TranscriptJsonPath -Raw | ConvertFrom-Json
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
        [string]$RequestedTranslationProvider,
        [string]$TranslationProviderSelectionSource,
        [string]$TranslationProviderResolutionNote,
        [string]$TranslationProvider,
        [string]$OpenAiModel,
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

    $null = Invoke-PhaseAction -Name "Preflight" -Detail $audioItem.Name -Action {
        $phaseHasAudio = Test-VideoHasAudio -FFprobeExe $FFprobeExe -VideoPath $audioItem.FullName
        if (-not $phaseHasAudio) {
            throw "Source file does not contain a readable audio stream."
        }

        $phaseDuration = Get-VideoDurationSeconds -FFprobeExe $FFprobeExe -VideoPath $audioItem.FullName
        Write-Log ("Source duration: {0}" -f (Format-DurationHuman $phaseDuration))
    }

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

    $whisperMode = "CPU"
    $transcriptResult = Invoke-PhaseAction -Name "Transcript" -Detail $audioItem.Name -Action {
        if ((Test-Path -LiteralPath $originalTranscriptSrt) -and (Test-Path -LiteralPath $originalTranscriptJson) -and (Test-Path -LiteralPath $originalTranscriptText)) {
            Write-Log "Transcript files already exist. Skipping Whisper transcription."
            return [PSCustomObject]@{
                Device   = "existing"
                JsonPath = $originalTranscriptJson
                SrtPath  = $originalTranscriptSrt
                TextPath = $originalTranscriptText
                Language = ""
                GpuError = ""
            }
        }

        Write-Log ("Generating transcript with Whisper on {0}..." -f $(if ($CanUseWhisperGpu) { "GPU if available" } else { "CPU" }))
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

    if ($transcriptResult.Device -eq "cuda") {
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
    $requestedProvider = [string]$TranslationProvider

    if ($requestedProvider -eq "OpenAI" -and -not (Test-OpenAiTranslationAvailable)) {
        throw (Get-OpenAiSetupInstructionsText -ProviderLabel "OpenAI translation")
    }

    foreach ($targetLanguage in $normalizedTargets) {
        $providerUsed = $null
        if ($targetLanguage -eq $detectedLanguage) {
            $providerUsed = "Original transcript copy"
        }
        elseif ($requestedProvider -eq "OpenAI") {
            $providerUsed = "OpenAI"
        }
        elseif ($requestedProvider -eq "Local") {
            if ($targetLanguage -eq "en") {
                if (-not (Test-WhisperModelSupportsTranslation -ModelName $ModelName)) {
                    throw "Local translation to English needs a multilingual Whisper model. Pick a model like 'base' or 'small', or use -TranslationProvider OpenAI."
                }

                $providerUsed = "Local (Whisper audio translation)"
            }
            else {
                $argosStatus = Ensure-ArgosTranslationSupport `
                    -PythonCommand $PythonCommand `
                    -SourceLanguageCode $detectedLanguage `
                    -TargetLanguageCode $targetLanguage `
                    -InteractiveMode:$InteractiveMode `
                    -HeartbeatSeconds $HeartbeatSeconds

                if ($argosStatus -eq "skip") {
                    Write-Log ("Skipping translation target '{0}' because local Argos support was not installed." -f $targetLanguage) "WARN"
                    continue
                }

                $providerUsed = "Local (Argos Translate)"
            }
        }
        else {
            if (Test-OpenAiTranslationAvailable) {
                $providerUsed = "OpenAI"
            }
            elseif ($targetLanguage -eq "en") {
                if (-not (Test-WhisperModelSupportsTranslation -ModelName $ModelName)) {
                    throw "Auto translation fell back to Local, but the selected Whisper model is English-only. Pick a multilingual model like 'base' or 'small', or set OPENAI_API_KEY."
                }

                $providerUsed = "Local (Whisper audio translation)"
            }
            else {
                $argosStatus = Ensure-ArgosTranslationSupport `
                    -PythonCommand $PythonCommand `
                    -SourceLanguageCode $detectedLanguage `
                    -TargetLanguageCode $targetLanguage `
                    -InteractiveMode:$InteractiveMode `
                    -HeartbeatSeconds $HeartbeatSeconds

                if ($argosStatus -eq "skip") {
                    Write-Log ("Skipping translation target '{0}' because local Argos support was not installed." -f $targetLanguage) "WARN"
                    continue
                }

                $providerUsed = "Local (Argos Translate)"
            }
        }

        Write-Log ("Translation provider for {0}: {1} (mode: {2})" -f $targetLanguage, $providerUsed, $TranslationProvider)

        $translationFolder = Join-Path $translationsFolder $targetLanguage
        Ensure-Directory $translationsFolder
        Ensure-Directory $translationFolder

        Invoke-PhaseAction -Name "Translation" -Detail ("{0} -> {1}" -f $audioItem.Name, $targetLanguage) -Action {
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
                return
            }

            if ($providerUsed -eq "Local (Whisper audio translation)") {
                $tempJsonName = "transcript_whisper_translate.json"
                $tempSrtName = "transcript_whisper_translate.srt"
                $tempTextName = "transcript_whisper_translate.txt"
                $translateResult = Invoke-PythonWhisperTranscript `
                    -PythonCommand $PythonCommand `
                    -AudioPath $reviewAudioPath `
                    -TranscriptFolder $translationFolder `
                    -ModelName $ModelName `
                    -LanguageCode $LanguageCode `
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

                return
            }

            if ($providerUsed -eq "Local (Argos Translate)") {
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
                return
            }

            $targetDisplayName = Get-LanguageDisplayName -Code $targetLanguage
            $sourceDisplayName = Get-LanguageDisplayName -Code $detectedLanguage
            $translatedSegments = Invoke-OpenAiSegmentTranslation `
                -Segments $transcriptData.Segments `
                -SourceLanguage $sourceDisplayName `
                -TargetLanguage $targetDisplayName `
                -Model $OpenAiModel `
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
        } | Out-Null

        [void]$completedTargets.Add($targetLanguage)
        [void]$translationProviderDetails.Add(("{0}={1}" -f $targetLanguage, $providerUsed))
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
    $translationProviderText = if ($completedTargets.Count -eq 0) {
        "none"
    }
    else {
        $translationProviderDetails -join "; "
    }

    Invoke-PhaseAction -Name "README" -Detail $audioItem.Name -Action {
        New-CodexReadme `
            -ReadmePath $readmeFile `
            -AudioFileName $audioItem.Name `
            -RawPresent $rawPresent `
            -DetectedLanguage $detectedLanguage `
            -TranslationTargets @($completedTargets) `
            -TranslationProviderDetails $translationProviderText `
            -CommentsSummary $commentsSummary
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
        -TranslationTargets ((@($completedTargets)) -join ", ") `
        -TranslationProvider $translationProviderText `
        -CommentsText $commentsTextPath `
        -CommentsJson $commentsJsonPath `
        -CommentsSummary $commentsSummary `
        -WhisperMode $whisperMode

    return [PSCustomObject]@{
        SourceAudioName     = $audioItem.Name
        OutputFolderName    = $safeBaseName
        OutputPath          = $audioOutputRoot
        ReviewAudioMode     = $reviewAudioMode
        WhisperMode         = $whisperMode
        SegmentCount        = $segmentCount
        DetectedLanguage    = $detectedLanguage
        TranslationTargets  = @($completedTargets)
        TranslationProvider = $translationProviderText
        CommentsSummary     = $commentsSummary
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

if ($translationTargets.Count -gt 0 -and -not $PSBoundParameters.ContainsKey("TranslationProvider") -and -not $NoPrompt) {
    $TranslationProvider = Get-InteractiveTranslationProvider -DefaultValue "Auto" -WasExplicitSelection ([ref]$translationProviderWasExplicit)
}

if ($translationTargets.Count -gt 0 -and $PSBoundParameters.ContainsKey("WhisperModel") -and -not (Test-WhisperModelSupportsTranslation -ModelName $WhisperModel)) {
    throw "Translation needs a multilingual Whisper model. The selected model '$WhisperModel' is English-only. Use a model like 'base' or 'small' instead."
}

$translationProviderResolution = [PSCustomObject]@{
    RequestedProvider = $TranslationProvider
    EffectiveProvider = $TranslationProvider
    SelectionSource   = if ($translationProviderWasExplicit) { "explicit" } else { "default" }
    ResolutionNote    = $null
}
if ($translationTargets.Count -gt 0) {
    $translationProviderResolution = Resolve-TranslationProviderRequest `
        -RequestedProvider $TranslationProvider `
        -WasExplicitlySet:$translationProviderWasExplicit `
        -InteractiveMode:$(-not $NoPrompt)
    $TranslationProvider = $translationProviderResolution.EffectiveProvider
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
if ($translationTargets.Count -gt 0) {
    Write-Log ("Translation targets selected: {0}" -f ($translationTargets -join ", "))
    Write-Log ("Requested translation provider: {0} ({1})" -f $translationProviderResolution.RequestedProvider, $translationProviderResolution.SelectionSource)
    if ($TranslationProvider -ne $translationProviderResolution.RequestedProvider) {
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
            $value = Read-Host "If comments are available for a YouTube source, save them in the package too? (y/N)"
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $doIncludeComments = $value.Trim() -match '^(y|yes)$'
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
                    $value = Read-Host "If comments are available for a YouTube source, save them in the package too? (y/N)"
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        $doIncludeComments = $value.Trim() -match '^(y|yes)$'
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

    if ($audioItems.Count -gt 0) {
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
    Write-Host ("Whisper path selected:           {0}" -f $(if ($canUseWhisperGpu) { "GPU preferred with CPU fallback" } else { "CPU fallback" }))
    Write-Host ("Heartbeat interval:              {0} seconds" -f $HeartbeatSeconds)
    Write-Host ("Input source:                    {0}" -f $inputSourceDisplay)
    if ($downloadedInputPaths.Count -gt 0) {
        Write-Host ("Downloaded input cache:          {0}" -f ($downloadedInputPaths -join "; "))
        Write-Host ("Downloaded source type:          {0}" -f ($downloadedInputKinds -join ", "))
        Write-Host ("Downloaded audio count:          {0}" -f $downloadedInputCount)
    }
    Write-Host ("Output folder:                   {0}" -f $OutputFolder)
    Write-Host ("Translation targets:             {0}" -f $(if ($translationTargets.Count -gt 0) { $translationTargets -join ", " } else { "none" }))
    Write-Host ("Translation provider:            {0}" -f $TranslationProvider)
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
                -RequestedTranslationProvider $translationProviderResolution.RequestedProvider `
                -TranslationProviderSelectionSource $translationProviderResolution.SelectionSource `
                -TranslationProviderResolutionNote $translationProviderResolution.ResolutionNote `
                -TranslationProvider $TranslationProvider `
                -OpenAiModel $OpenAiModel `
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
    Write-Host ("Successful packages: {0}" -f $processedItems.Count)
    Write-Host ("Failed packages:     {0}" -f $failedItems.Count)
    Write-Host ("Output root:         {0}" -f $OutputFolder)
    Write-Host ("Master README:       {0}" -f $masterReadme)
    Write-Host ("Processing summary:  {0}" -f $summaryCsv)

    foreach ($item in $processedItems) {
        Write-Host ("PASS {0}" -f $item.SourceAudioName) -ForegroundColor Green
        Write-Host ("  Output:  {0}" -f $item.OutputPath)
        Write-Host ("  Review:  {0}" -f $item.ReviewAudioMode)
        Write-Host ("  Whisper: {0}" -f $item.WhisperMode)
        Write-Host ("  Lang:    {0}" -f $item.DetectedLanguage)
        Write-Host ("  Xlate:   {0}" -f $(if ($item.TranslationTargets.Count -gt 0) { $item.TranslationTargets -join ", " } else { "none" }))
        Write-Host ("  Provider:{0}" -f $(if ([string]::IsNullOrWhiteSpace($item.TranslationProvider) -or $item.TranslationProvider -eq "none") { " none" } else { " $($item.TranslationProvider)" }))
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

    if ($failedItems.Count -gt 0 -or $processedItems.Count -eq 0) {
        Write-Log ("FAIL: Processing completed with {0} failure(s)." -f $failedItems.Count) "ERROR"
        throw ("Processing completed with {0} failure(s)." -f $failedItems.Count)
    }

    Write-Log ("PASS: All {0} audio item(s) processed successfully. Output root: {1}" -f $processedItems.Count, $OutputFolder)
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
