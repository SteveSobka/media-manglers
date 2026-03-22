param(
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $true)]
    [string]$VideoPath,

    [double]$FrameIntervalSeconds = 0.5,
    [int]$MinimumFrameCount = 3
)

$ErrorActionPreference = "Stop"

function Get-FrameIntervalLabel {
    param([double]$Value)

    return $Value.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture) -replace '\.', 'p'
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

function Assert-File {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing required file: $Label ($Path)"
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) {
        throw "Required file is empty: $Label ($Path)"
    }
}

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    throw "Output root not found: $OutputRoot"
}

if (-not (Test-Path -LiteralPath $VideoPath)) {
    throw "Video path not found: $VideoPath"
}

$videoItem = Get-Item -LiteralPath $VideoPath
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($videoItem.Name)
$packageFolderName = Get-SafeFolderName -Name $baseName
$framesFolderName = "frames_{0}s" -f (Get-FrameIntervalLabel -Value $FrameIntervalSeconds)
$packageRoot = Join-Path $OutputRoot $packageFolderName

if (-not (Test-Path -LiteralPath $packageRoot)) {
    throw "Package folder not found: $packageRoot"
}

$proxyPath = Join-Path $packageRoot "proxy\review_proxy_1280.mp4"
$audioPath = Join-Path $packageRoot "audio\audio.mp3"
$transcriptSrt = Join-Path $packageRoot "transcript\transcript.srt"
$transcriptJson = Join-Path $packageRoot "transcript\transcript.json"
$frameIndexCsv = Join-Path $packageRoot "frame_index.csv"
$readmePath = Join-Path $packageRoot "README_FOR_CODEX.txt"
$logPath = Join-Path $packageRoot "script_run.log"
$framesFolder = Join-Path $packageRoot $framesFolderName

Assert-File -Path $proxyPath -Label "proxy video"
Assert-File -Path $audioPath -Label "audio mp3"
Assert-File -Path $transcriptSrt -Label "transcript srt"
Assert-File -Path $transcriptJson -Label "transcript json"
Assert-File -Path $frameIndexCsv -Label "frame index csv"
Assert-File -Path $readmePath -Label "readme"
Assert-File -Path $logPath -Label "script log"

if (-not (Test-Path -LiteralPath $framesFolder)) {
    throw "Frames folder not found: $framesFolder"
}

$frames = @(Get-ChildItem -LiteralPath $framesFolder -Filter "frame_*.jpg" -File | Sort-Object Name)
if ($frames.Count -lt $MinimumFrameCount) {
    throw "Expected at least $MinimumFrameCount extracted frames in $framesFolder but found $($frames.Count)."
}

foreach ($frame in $frames | Select-Object -First 3) {
    if ($frame.Length -le 0) {
        throw "Frame file is empty: $($frame.FullName)"
    }
}

$summaryCsv = Join-Path $OutputRoot "PROCESSING_SUMMARY.csv"
$masterReadme = Join-Path $OutputRoot "CODEX_MASTER_README.txt"
Assert-File -Path $summaryCsv -Label "processing summary"
Assert-File -Path $masterReadme -Label "master readme"

Write-Host "PASS validation completed." -ForegroundColor Green
Write-Host ("Package root: {0}" -f $packageRoot)
Write-Host ("Frames found: {0}" -f $frames.Count)
