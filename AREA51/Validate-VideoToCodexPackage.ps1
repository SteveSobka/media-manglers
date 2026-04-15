param(
    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [string]$VideoPath,

    [string]$PackageFolderName,

    [double]$FrameIntervalSeconds = 0.5,
    [int]$MinimumFrameCount = 3
)

$ErrorActionPreference = "Stop"

function Get-LatestSmokeOutputFolder {
    param([string[]]$SearchRoots)

    foreach ($root in ($SearchRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        $latestSmoke = Get-ChildItem -LiteralPath $root -Directory |
            Where-Object { $_.Name -like 'smoke-*' } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($latestSmoke) {
            return $latestSmoke.FullName
        }
    }

    return $null
}

function Resolve-OutputRootPath {
    param(
        [string]$Path,
        [string]$DefaultSmokeRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        return (Resolve-Path -LiteralPath $Path).ProviderPath
    }

    $searchRoots = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $parent = Split-Path -Path $Path -Parent
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            [void]$searchRoots.Add($parent)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($DefaultSmokeRoot)) {
        [void]$searchRoots.Add($DefaultSmokeRoot)
    }

    $latestSmoke = Get-LatestSmokeOutputFolder -SearchRoots @($searchRoots)
    if ($latestSmoke) {
        return $latestSmoke
    }

    return $Path
}

function Get-PackageDirectories {
    param([string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $RootPath -Directory | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName "README_FOR_CODEX.txt")) -or
        (Test-Path -LiteralPath (Join-Path $_.FullName "frame_index.csv"))
    } | Sort-Object Name)
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).ProviderPath
$defaultSmokeRoot = Join-Path $repoRoot "test-output"

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

function Test-VideoHasAudio {
    param([string]$VideoPath)

    $ffprobeExe = "C:\APPS\ffmpeg\bin\ffprobe.exe"
    if (-not (Test-Path -LiteralPath $ffprobeExe)) {
        return $true
    }

    $output = & $ffprobeExe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 $VideoPath
    return ($output -match 'audio')
}

$OutputRoot = Resolve-OutputRootPath -Path $OutputRoot -DefaultSmokeRoot $defaultSmokeRoot

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    throw "Output root not found: $OutputRoot. Run .\AREA51\Run-SmokeTest.ps1 first, or pass -OutputRoot to an existing package output folder."
}

$videoItem = $null
$packageDirectories = Get-PackageDirectories -RootPath $OutputRoot
if (-not [string]::IsNullOrWhiteSpace($VideoPath)) {
    if (-not (Test-Path -LiteralPath $VideoPath)) {
        throw "Video path not found: $VideoPath"
    }

    $videoItem = Get-Item -LiteralPath $VideoPath
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($videoItem.Name)
    $packageFolderName = Get-SafeFolderName -Name $baseName
}
elseif (-not [string]::IsNullOrWhiteSpace($PackageFolderName)) {
    $packageFolderName = Get-SafeFolderName -Name $PackageFolderName
}
elseif ($packageDirectories.Count -eq 1) {
    $packageFolderName = $packageDirectories[0].Name
}
elseif ($packageDirectories.Count -gt 1) {
    $choices = $packageDirectories | ForEach-Object { $_.Name }
    throw ("Multiple package folders found under {0}. Re-run with -PackageFolderName. Choices: {1}" -f $OutputRoot, ($choices -join ", "))
}
else {
    throw "No package folders found under: $OutputRoot"
}

$framesFolderName = "frames_{0}s" -f (Get-FrameIntervalLabel -Value $FrameIntervalSeconds)
$packageRoot = Join-Path $OutputRoot $packageFolderName

if (-not (Test-Path -LiteralPath $packageRoot)) {
    $choices = $packageDirectories | ForEach-Object { $_.Name }
    if ($choices.Count -gt 0) {
        throw ("Package folder not found: {0}. Available package folders: {1}" -f $packageRoot, ($choices -join ", "))
    }
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
$hasAudio = if ($videoItem) { Test-VideoHasAudio -VideoPath $videoItem.FullName } else { $true }

Assert-File -Path $proxyPath -Label "proxy video"
Assert-File -Path $frameIndexCsv -Label "frame index csv"
Assert-File -Path $readmePath -Label "readme"
Assert-File -Path $logPath -Label "script log"

if ($hasAudio) {
    Assert-File -Path $audioPath -Label "audio mp3"
    Assert-File -Path $transcriptSrt -Label "transcript srt"
    Assert-File -Path $transcriptJson -Label "transcript json"
}

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
Write-Host ("Output root:  {0}" -f $OutputRoot)
Write-Host ("Package root: {0}" -f $packageRoot)
Write-Host ("Frames found: {0}" -f $frames.Count)
