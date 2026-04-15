param(
    [ValidateSet("Video", "Audio", "All")]
    [string]$App = "All"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).ProviderPath
$distFolder = Join-Path $repoRoot "dist"
$releaseRoot = Join-Path $distFolder "release"
$versionFile = Join-Path $repoRoot "VERSION"
$modulePath = Join-Path $HOME "Documents\PowerShell\Modules\ps2exe\1.0.17\ps2exe.psm1"

if (-not (Test-Path -LiteralPath $versionFile)) {
    throw "Version file not found: $versionFile"
}

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "ps2exe module not found at: $modulePath"
}

$appVersion = (Get-Content -LiteralPath $versionFile | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($appVersion)) {
    throw "Version file is empty: $versionFile"
}

$releaseNotes = Join-Path $repoRoot ("RELEASE_NOTES_v{0}.txt" -f $appVersion)
if (-not (Test-Path -LiteralPath $releaseNotes)) {
    throw "Release notes file not found: $releaseNotes"
}

$appConfigs = @(
    [PSCustomObject]@{
        Key             = "Video"
        ScriptFile      = "Video Mangler.ps1"
        LocalExeName    = "Video Mangler.exe"
        ReleaseExeName  = "Video-Mangler.exe"
        ReleaseZipName  = "Video-Mangler-v{0}.zip" -f $appVersion
        ReleaseFolder   = "Video-Mangler-v{0}" -f $appVersion
        IconFile        = "assets\Video Mangler.ico"
        ProductName     = "Video Mangler"
        Description     = "Builds review packages from local videos, remote URLs, and YouTube inputs."
        AppGuide        = "VIDEO_MANGLER.txt"
    }
    [PSCustomObject]@{
        Key             = "Audio"
        ScriptFile      = "Audio Mangler.ps1"
        LocalExeName    = "Audio Mangler.exe"
        ReleaseExeName  = "Audio-Mangler.exe"
        ReleaseZipName  = "Audio-Mangler-v{0}.zip" -f $appVersion
        ReleaseFolder   = "Audio-Mangler-v{0}" -f $appVersion
        IconFile        = "assets\Audio Mangler.ico"
        ProductName     = "Audio Mangler"
        Description     = "Builds transcript-first review packages from local audio, direct URLs, pages, and YouTube inputs."
        AppGuide        = "AUDIO_MANGLER.txt"
    }
)

$selectedApps = if ($App -eq "All") {
    $appConfigs
}
else {
    @($appConfigs | Where-Object { $_.Key -eq $App })
}

if ($selectedApps.Count -eq 0) {
    throw "No app configuration matched: $App"
}

New-Item -ItemType Directory -Path $distFolder -Force | Out-Null
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

Import-Module $modulePath -Force

foreach ($appConfig in $selectedApps) {
    $inputFile = Join-Path $repoRoot $appConfig.ScriptFile
    $outputFile = Join-Path $distFolder $appConfig.LocalExeName
    $iconFile = Join-Path $repoRoot $appConfig.IconFile
    $releaseFolder = Join-Path $releaseRoot $appConfig.ReleaseFolder
    $releaseZip = Join-Path $releaseRoot $appConfig.ReleaseZipName
    $releaseExe = Join-Path $releaseRoot $appConfig.ReleaseExeName
    $appFolder = Join-Path $releaseFolder "app"
    $docsFolder = Join-Path $releaseFolder "docs"

    foreach ($requiredPath in @($inputFile, $iconFile, (Join-Path $repoRoot $appConfig.AppGuide), (Join-Path $repoRoot "README.txt"), (Join-Path $repoRoot "THIRD_PARTY_NOTICES.txt"), (Join-Path $repoRoot "LICENSE"))) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required file not found: $requiredPath"
        }
    }

    if (Test-Path -LiteralPath $outputFile) {
        Remove-Item -LiteralPath $outputFile -Force
    }

    Invoke-ps2exe `
        -inputFile $inputFile `
        -outputFile $outputFile `
        -iconFile $iconFile `
        -title $appConfig.ProductName `
        -product $appConfig.ProductName `
        -description $appConfig.Description `
        -company "Media Manglers" `
        -copyright "Copyright (c) 2026 Media Manglers Contributors" `
        -version $appVersion

    if (Test-Path -LiteralPath $releaseFolder) {
        Remove-Item -LiteralPath $releaseFolder -Recurse -Force
    }

    if (Test-Path -LiteralPath $releaseZip) {
        Remove-Item -LiteralPath $releaseZip -Force
    }

    if (Test-Path -LiteralPath $releaseExe) {
        Remove-Item -LiteralPath $releaseExe -Force
    }

    New-Item -ItemType Directory -Path $appFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $docsFolder -Force | Out-Null

    Copy-Item -LiteralPath $outputFile -Destination (Join-Path $appFolder $appConfig.LocalExeName) -Force
    Copy-Item -LiteralPath $outputFile -Destination $releaseExe -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "README.txt") -Destination (Join-Path $docsFolder "README.txt") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot $appConfig.AppGuide) -Destination (Join-Path $docsFolder $appConfig.AppGuide) -Force
    Copy-Item -LiteralPath $releaseNotes -Destination (Join-Path $docsFolder ([System.IO.Path]::GetFileName($releaseNotes))) -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "THIRD_PARTY_NOTICES.txt") -Destination (Join-Path $docsFolder "THIRD_PARTY_NOTICES.txt") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination (Join-Path $docsFolder "LICENSE.txt") -Force
    Copy-Item -LiteralPath $versionFile -Destination (Join-Path $docsFolder "VERSION.txt") -Force

    Compress-Archive -LiteralPath $releaseFolder -DestinationPath $releaseZip -CompressionLevel Optimal

    Write-Host ("Built {0}: {1}" -f $appConfig.ProductName, $outputFile) -ForegroundColor Green
    Write-Host ("Release exe: {0}" -f $releaseExe) -ForegroundColor Green
    Write-Host ("Release zip: {0}" -f $releaseZip) -ForegroundColor Green
}
