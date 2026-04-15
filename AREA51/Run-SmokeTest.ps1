param(
    [string]$TestMediaFolder = (Join-Path $PSScriptRoot "..\test_media"),
    [string]$VideoPath,
    [string]$RemoteSampleUrl = "https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov",
    [double]$FrameIntervalSeconds = 0.5,
    [string]$WhisperModel = "base.en",
    [int]$HeartbeatSeconds = 10,
    [switch]$CopyRawVideo,
    [switch]$SkipEstimate,
    [switch]$AllMedia
)

$ErrorActionPreference = "Stop"

function Get-SmokeTestMediaFiles {
    param([string]$FolderPath)

    $extensions = @(".mp4", ".mov", ".mkv", ".avi", ".m4v", ".webm")
    return @(Get-ChildItem -LiteralPath $FolderPath -File | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)
}

function Get-RepresentativeSmokeTestMedia {
    param([System.IO.FileInfo[]]$Files)

    foreach ($preferredName in @("ToS-4k-1920.mov", "bbb_sunflower_1080p_60fps_normal.mp4")) {
        $preferred = $Files | Where-Object { $_.Name -eq $preferredName } | Select-Object -First 1
        if ($preferred) {
            return $preferred
        }
    }

    return $Files | Sort-Object Length -Descending | Select-Object -First 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).ProviderPath
$videoScript = Join-Path $repoRoot "video_to_codex_package.ps1"
$validator = Join-Path $PSScriptRoot "Validate-VideoToCodexPackage.ps1"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputRoot = Join-Path $repoRoot ("test-output\smoke-{0}" -f $timestamp)
$usingRemoteSample = $false
$remotePackageFolderName = $null

if (-not (Test-Path -LiteralPath $videoScript)) {
    throw "Main script not found: $videoScript"
}

if (-not (Test-Path -LiteralPath $validator)) {
    throw "Validator script not found: $validator"
}

$mediaFiles = @()
if (Test-Path -LiteralPath $TestMediaFolder) {
    $mediaFiles = Get-SmokeTestMediaFiles -FolderPath $TestMediaFolder
}

$selectedFiles = @()
$inputTarget = $null

if ($VideoPath) {
    if (-not (Test-Path -LiteralPath $VideoPath)) {
        throw "Requested video path not found: $VideoPath"
    }
    $selectedFiles = @((Get-Item -LiteralPath $VideoPath))
    $inputTarget = $selectedFiles[0].FullName
}
elseif ($AllMedia) {
    if (-not (Test-Path -LiteralPath $TestMediaFolder)) {
        throw "Test media folder not found: $TestMediaFolder"
    }
    if ($mediaFiles.Count -eq 0) {
        throw "No supported media files found in $TestMediaFolder"
    }
    $selectedFiles = $mediaFiles
    $inputTarget = (Resolve-Path -LiteralPath $TestMediaFolder).ProviderPath
}
elseif ($mediaFiles.Count -gt 0) {
    $representative = Get-RepresentativeSmokeTestMedia -Files $mediaFiles
    $selectedFiles = @($representative)
    $inputTarget = $representative.FullName
}
else {
    $usingRemoteSample = $true
    $inputTarget = $RemoteSampleUrl
    $remotePackageFolderName = [System.IO.Path]::GetFileNameWithoutExtension(([System.Uri]$RemoteSampleUrl).AbsolutePath)
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

Write-Host ("Smoke test output root: {0}" -f $outputRoot) -ForegroundColor Cyan
if (Test-Path -LiteralPath $TestMediaFolder) {
    Write-Host ("Test media folder:      {0}" -f (Resolve-Path -LiteralPath $TestMediaFolder).ProviderPath) -ForegroundColor Cyan
}
else {
    Write-Host ("Test media folder:      {0}" -f $TestMediaFolder) -ForegroundColor DarkGray
}
if ($usingRemoteSample) {
    Write-Host ("Remote sample URL:      {0}" -f $RemoteSampleUrl) -ForegroundColor Cyan
}
elseif ($AllMedia) {
    Write-Host ("Mode:                   all media ({0} files)" -f $selectedFiles.Count) -ForegroundColor Cyan
}
else {
    Write-Host ("Video under test:       {0}" -f $selectedFiles[0].FullName) -ForegroundColor Cyan
}

$args = New-Object System.Collections.Generic.List[string]
[void]$args.Add("-NoProfile")
[void]$args.Add("-ExecutionPolicy")
[void]$args.Add("Bypass")
[void]$args.Add("-File")
[void]$args.Add($videoScript)
if ($usingRemoteSample) {
    [void]$args.Add("-InputUrl")
}
else {
    [void]$args.Add("-InputPath")
}
[void]$args.Add($inputTarget)
[void]$args.Add("-OutputFolder")
[void]$args.Add($outputRoot)
[void]$args.Add("-FrameIntervalSeconds")
[void]$args.Add($FrameIntervalSeconds.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture))
[void]$args.Add("-WhisperModel")
[void]$args.Add($WhisperModel)
[void]$args.Add("-HeartbeatSeconds")
[void]$args.Add($HeartbeatSeconds.ToString())
[void]$args.Add("-NoPrompt")

if ($CopyRawVideo) {
    [void]$args.Add("-CopyRawVideo")
}

if ($SkipEstimate) {
    [void]$args.Add("-SkipEstimate")
}

& powershell @($args)
if ($LASTEXITCODE -ne 0) {
    throw "Smoke test packaging run failed with exit code $LASTEXITCODE"
}

if ($usingRemoteSample) {
    & $validator -OutputRoot $outputRoot -PackageFolderName $remotePackageFolderName -FrameIntervalSeconds $FrameIntervalSeconds
}
else {
    foreach ($file in $selectedFiles) {
        & $validator -OutputRoot $outputRoot -VideoPath $file.FullName -FrameIntervalSeconds $FrameIntervalSeconds
    }
}

Write-Host ("PASS smoke test completed. Output root: {0}" -f $outputRoot) -ForegroundColor Green
