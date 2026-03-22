param(
    [string]$VideoPath = (Join-Path $PSScriptRoot "..\2026-03-17_18-59-11.mkv"),
    [double]$FrameIntervalSeconds = 0.5,
    [string]$WhisperModel = "base.en",
    [switch]$CopyRawVideo,
    [switch]$SkipEstimate
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).ProviderPath
$videoScript = Join-Path $repoRoot "video_to_codex_package.ps1"
$validator = Join-Path $PSScriptRoot "Validate-VideoToCodexPackage.ps1"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputRoot = Join-Path $repoRoot ("test-output\smoke-{0}" -f $timestamp)

if (-not (Test-Path -LiteralPath $videoScript)) {
    throw "Main script not found: $videoScript"
}

if (-not (Test-Path -LiteralPath $validator)) {
    throw "Validator script not found: $validator"
}

if (-not (Test-Path -LiteralPath $VideoPath)) {
    throw "Smoke test video not found: $VideoPath"
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

Write-Host ("Smoke test output root: {0}" -f $outputRoot) -ForegroundColor Cyan
Write-Host ("Video under test:       {0}" -f (Resolve-Path -LiteralPath $VideoPath).ProviderPath) -ForegroundColor Cyan

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $videoScript,
    "-InputPath", (Resolve-Path -LiteralPath $VideoPath).ProviderPath,
    "-OutputFolder", $outputRoot,
    "-FrameIntervalSeconds", $FrameIntervalSeconds.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture),
    "-WhisperModel", $WhisperModel,
    "-NoPrompt"
)

if ($CopyRawVideo) {
    $args += "-CopyRawVideo"
}

if ($SkipEstimate) {
    $args += "-SkipEstimate"
}

& powershell @args
if ($LASTEXITCODE -ne 0) {
    throw "Smoke test packaging run failed with exit code $LASTEXITCODE"
}

& $validator -OutputRoot $outputRoot -VideoPath (Resolve-Path -LiteralPath $VideoPath).ProviderPath -FrameIntervalSeconds $FrameIntervalSeconds

Write-Host ("PASS smoke test completed. Output root: {0}" -f $outputRoot) -ForegroundColor Green
