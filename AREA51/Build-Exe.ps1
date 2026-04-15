$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).ProviderPath
$inputFile = Join-Path $repoRoot "video_to_codex_package.ps1"
$distFolder = Join-Path $repoRoot "dist"
$outputFile = Join-Path $distFolder "video_to_codex_package.exe"
$iconFile = Join-Path $repoRoot "assets\video_to_codex_package.ico"
$versionFile = Join-Path $repoRoot "VERSION"
$modulePath = Join-Path $HOME "Documents\PowerShell\Modules\ps2exe\1.0.17\ps2exe.psm1"
$releaseRoot = Join-Path $distFolder "release"

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

$releaseName = "media-manglers-v{0}" -f $appVersion
$releaseFolder = Join-Path $releaseRoot $releaseName
$releaseZip = Join-Path $releaseRoot ("{0}.zip" -f $releaseName)
$appFolder = Join-Path $releaseFolder "app"
$docsFolder = Join-Path $releaseFolder "docs"
$releaseFiles = @(
    @{ Source = $outputFile; Destination = Join-Path $appFolder "video_to_codex_package.exe" },
    @{ Source = $repoRoot; Relative = "README.txt"; Destination = Join-Path $docsFolder "README.txt" },
    @{ Source = $repoRoot; Relative = "RELEASE_NOTES_v{0}.txt" -f $appVersion; Destination = Join-Path $docsFolder ("RELEASE_NOTES_v{0}.txt" -f $appVersion) },
    @{ Source = $repoRoot; Relative = "THIRD_PARTY_NOTICES.txt"; Destination = Join-Path $docsFolder "THIRD_PARTY_NOTICES.txt" },
    @{ Source = $repoRoot; Relative = "LICENSE"; Destination = Join-Path $docsFolder "LICENSE.txt" },
    @{ Source = $repoRoot; Relative = "VERSION"; Destination = Join-Path $docsFolder "VERSION.txt" }
)

New-Item -ItemType Directory -Path $distFolder -Force | Out-Null
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

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

if (Test-Path -LiteralPath $releaseFolder) {
    Remove-Item -LiteralPath $releaseFolder -Recurse -Force
}

if (Test-Path -LiteralPath $releaseZip) {
    Remove-Item -LiteralPath $releaseZip -Force
}

New-Item -ItemType Directory -Path $appFolder -Force | Out-Null
New-Item -ItemType Directory -Path $docsFolder -Force | Out-Null

foreach ($releaseFile in $releaseFiles) {
    $sourcePath = if ($releaseFile.ContainsKey("Relative")) {
        Join-Path $releaseFile.Source $releaseFile.Relative
    }
    else {
        $releaseFile.Source
    }

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Release package source file not found: $sourcePath"
    }

    Copy-Item -LiteralPath $sourcePath -Destination $releaseFile.Destination -Force
}

Compress-Archive -LiteralPath $releaseFolder -DestinationPath $releaseZip -CompressionLevel Optimal

Write-Host ("Wrote executable: {0}" -f $outputFile) -ForegroundColor Green
Write-Host ("Executable version: {0}" -f $appVersion) -ForegroundColor Cyan
Write-Host ("Wrote release folder: {0}" -f $releaseFolder) -ForegroundColor Green
Write-Host ("Wrote release zip: {0}" -f $releaseZip) -ForegroundColor Green
