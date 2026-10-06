# Deploy only runtime addon files from this repo to the live RoR AddOns folder.
# Copies: WarTriage.mod + root runtime Lua + libs\
# Removes anything else under Dest (.git, docs, README, old backups, workspace files, etc.).
#
# Usage:
#   .\tools\deploy.ps1
#   .\tools\deploy.ps1 -WhatIf
#   .\tools\deploy.ps1 -Dest "D:\Games\...\Interface\AddOns\WarTriage"

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Dest = "C:\Users\talla\Games\Return of Reckoning\Interface\AddOns\WarTriage"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DestParent = Split-Path -Parent $Dest
$ModSrc = Join-Path $RepoRoot "WarTriage.mod"

$RootFiles = @(
    "WarTriage.mod",
    "WarTriage.lua",
    "WarTriage_Config.lua"
)

$RuntimeDirs = @(
    "libs"
)

if (-not (Test-Path -LiteralPath $ModSrc)) {
    throw "WarTriage.mod missing under $RepoRoot - refuse to deploy"
}
foreach ($name in $RootFiles) {
    $path = Join-Path $RepoRoot $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required runtime file missing: $name"
    }
}
foreach ($dir in $RuntimeDirs) {
    $path = Join-Path $RepoRoot $dir
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required runtime folder missing: $dir\"
    }
}
if (-not (Test-Path -LiteralPath $DestParent)) {
    throw "AddOns parent missing: $DestParent"
}
$destLeaf = Split-Path -Leaf $Dest
if ($destLeaf -ne "WarTriage") {
    throw "Dest must be a WarTriage folder (leaf name WarTriage), got: $destLeaf ($Dest)"
}
$destParentLeaf = Split-Path -Leaf $DestParent
if ($destParentLeaf -ne "AddOns") {
    throw "Dest parent must be an AddOns folder, got: $destParentLeaf ($DestParent)"
}

$repoFull = [System.IO.Path]::GetFullPath([string]$RepoRoot).TrimEnd('\', '/')
$destFull = [System.IO.Path]::GetFullPath($Dest).TrimEnd('\', '/')
if ($destFull.Equals($repoFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Dest must not be the git clone ($Dest)"
}
$repoPrefix = $repoFull + [IO.Path]::DirectorySeparatorChar
if ($destFull.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Dest must not be inside the git clone ($Dest)"
}

Write-Host "Repo:   $RepoRoot"
Write-Host "Dest:   $Dest"
Write-Host ("Copy:   " + ($RootFiles -join ", ") + " + " + (($RuntimeDirs | ForEach-Object { "$_\" }) -join " "))

if (-not $PSCmdlet.ShouldProcess($Dest, "Deploy runtime addon files and prune extras")) {
    exit 0
}

New-Item -ItemType Directory -Force -Path $Dest | Out-Null

function Invoke-RobocopyMirror {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $robocopyArgs = @(
        $Source,
        $Destination,
        "/MIR",
        "/XF", "*.bak", "*.tmp", "*.log", "Thumbs.db", ".DS_Store", "Desktop.ini",
        "/XD", "__pycache__",
        "/R:2", "/W:1",
        "/NFL", "/NDL", "/NP", "/NJH"
    )
    # Swallow robocopy stdout so callers only receive the exit code.
    & robocopy @robocopyArgs | Out-Null
    $rc = $LASTEXITCODE
    # Robocopy: 0-7 = success (with optional extras); >=8 = failure
    if ($rc -ge 8) {
        throw "robocopy failed ($Source -> $Destination) with exit code $rc"
    }
    return $rc
}

$lastRc = 0
foreach ($dir in $RuntimeDirs) {
    $src = Join-Path $RepoRoot $dir
    $dst = Join-Path $Dest $dir
    $lastRc = Invoke-RobocopyMirror -Source $src -Destination $dst
}

foreach ($name in $RootFiles) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $name) -Destination (Join-Path $Dest $name) -Force
}

# Keep Dest as a runtime-only tree: remove anything that is not an allowed root entry.
$allowed = @{}
foreach ($name in $RootFiles) { $allowed[$name] = $true }
foreach ($dir in $RuntimeDirs) { $allowed[$dir] = $true }

Get-ChildItem -LiteralPath $Dest -Force | ForEach-Object {
    if ($allowed.ContainsKey($_.Name)) { return }
    Write-Host "Prune: $($_.FullName)"
    Remove-Item -LiteralPath $_.FullName -Recurse -Force
}

$destMod = Join-Path $Dest "WarTriage.mod"
if (-not (Test-Path -LiteralPath $destMod)) {
    throw "Deploy incomplete: missing WarTriage.mod under $Dest"
}
foreach ($dir in $RuntimeDirs) {
    if (-not (Test-Path -LiteralPath (Join-Path $Dest $dir))) {
        throw "Deploy incomplete: missing $dir\ under $Dest"
    }
}

$fileCount = 0
foreach ($dir in $RuntimeDirs) {
    $fileCount += @(Get-ChildItem -LiteralPath (Join-Path $Dest $dir) -Recurse -File).Count
}
$fileCount += $RootFiles.Count

Write-Host "Deploy OK (runtime files: $fileCount, last robocopy exit $lastRc). Reload UI in-game (/reload)."
exit 0
