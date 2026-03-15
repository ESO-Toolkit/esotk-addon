# install-dev.ps1
# Copies the addon source files into the ESO AddOns directory for local development.
# The target AddOns path can be overridden via the ESO_ADDONS_DIR environment variable.

param(
    [string]$AddOnsDir = $env:ESO_ADDONS_DIR
)

$DefaultAddOnsDir = "C:\Users\$env:USERNAME\OneDrive\Documents\Elder Scrolls Online\live\AddOns"

if (-not $AddOnsDir) {
    $AddOnsDir = $DefaultAddOnsDir
}

$AddonName = "ESOtk"
$TargetDir = Join-Path $AddOnsDir $AddonName
$SourceDir = Split-Path $PSScriptRoot -Parent

Write-Host "Installing $AddonName dev build..."
Write-Host "  Source : $SourceDir"
Write-Host "  Target : $TargetDir"

if (-not (Test-Path $AddOnsDir)) {
    Write-Error "AddOns directory not found: $AddOnsDir`nSet the ESO_ADDONS_DIR environment variable to override."
    exit 1
}

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir | Out-Null
    Write-Host "  Created $TargetDir"
}

$Files = Get-ChildItem -Path $SourceDir -File | Where-Object { $_.Extension -in '.lua', '.txt' }

foreach ($File in $Files) {
    Copy-Item -Path $File.FullName -Destination $TargetDir -Force
    Write-Host "  Copied  $($File.Name)"
}

Write-Host ""
Write-Host "Done. $($Files.Count) file(s) installed to $TargetDir"
