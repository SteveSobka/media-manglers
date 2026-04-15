$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).ProviderPath
$inputFile = Join-Path $repoRoot "video_to_codex_package.ps1"
$distFolder = Join-Path $repoRoot "dist"
$outputFile = Join-Path $distFolder "video_to_codex_package.exe"
$modulePath = Join-Path $HOME "Documents\PowerShell\Modules\ps2exe\1.0.17\ps2exe.psm1"

if (-not (Test-Path -LiteralPath $inputFile)) {
    throw "Input script not found: $inputFile"
}

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "ps2exe module not found at: $modulePath"
}

New-Item -ItemType Directory -Path $distFolder -Force | Out-Null

Import-Module $modulePath -Force
Invoke-ps2exe -inputFile $inputFile -outputFile $outputFile

Write-Host ("Wrote executable: {0}" -f $outputFile) -ForegroundColor Green
