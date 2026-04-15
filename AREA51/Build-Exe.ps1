$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).ProviderPath
$inputFile = Join-Path $repoRoot "video_to_codex_package.ps1"
$distFolder = Join-Path $repoRoot "dist"
$outputFile = Join-Path $distFolder "video_to_codex_package.exe"
$iconFile = Join-Path $repoRoot "assets\video_to_codex_package.ico"
$versionFile = Join-Path $repoRoot "VERSION"
$modulePath = Join-Path $HOME "Documents\PowerShell\Modules\ps2exe\1.0.17\ps2exe.psm1"

if (-not (Test-Path -LiteralPath $inputFile)) {
    throw "Input script not found: $inputFile"
}

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "ps2exe module not found at: $modulePath"
}

if (-not (Test-Path -LiteralPath $iconFile)) {
    throw "Icon file not found: $iconFile"
}

if (-not (Test-Path -LiteralPath $versionFile)) {
    throw "Version file not found: $versionFile"
}

$appVersion = (Get-Content -LiteralPath $versionFile | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($appVersion)) {
    throw "Version file is empty: $versionFile"
}

New-Item -ItemType Directory -Path $distFolder -Force | Out-Null

Import-Module $modulePath -Force
Invoke-ps2exe `
    -inputFile $inputFile `
    -outputFile $outputFile `
    -iconFile $iconFile `
    -title "video_to_codex_package" `
    -product "media-manglers" `
    -description "Builds review packages from local videos, remote URLs, and YouTube inputs." `
    -company "Steve Sobka" `
    -copyright "Copyright (c) 2026 Steve Sobka" `
    -version $appVersion

Write-Host ("Wrote executable: {0}" -f $outputFile) -ForegroundColor Green
Write-Host ("Executable version: {0}" -f $appVersion) -ForegroundColor Cyan
