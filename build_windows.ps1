# Builds the Windows x64 release of Last Epoch Builder.
# Usage: .\build_windows.ps1 [-Godot <path to Godot 4.7 console exe>] [-Version 0.1.0]
# Needs the Godot 4.7 export templates. Output: build/LastEpochBuilder-<version>-windows-x64.zip
param(
    [string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "C:/Users/Admin/Documents/Godot_v4.7-stable_win64/Godot_v4.7-stable_win64_console.exe" }),
    [string]$Version = "0.1.0"
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$client = Join-Path $root "client"
$dataCopy = Join-Path $client "data/research"
$out = Join-Path $root "build/LastEpochBuilder"
$zip = Join-Path $root "build/LastEpochBuilder-$Version-windows-x64.zip"

# The client reads research/data from the repository in the editor; the export packs a copy (LE.research_dir).
if (Test-Path $dataCopy) { Remove-Item -Recurse -Force $dataCopy }
Copy-Item -Recurse (Join-Path $root "research/data") $dataCopy
try {
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    New-Item -ItemType Directory -Force $out | Out-Null
    & $Godot --headless --path $client --import | Out-Null
    & $Godot --headless --path $client --export-release "Windows Desktop" (Join-Path $out "LastEpochBuilder.exe")
    if ($LASTEXITCODE -ne 0) { throw "Godot export failed ($LASTEXITCODE)" }
}
finally {
    Remove-Item -Recurse -Force $dataCopy
}
Copy-Item (Join-Path $root "LICENSE") $out
Copy-Item (Join-Path $root "release/README.txt") $out
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip
Write-Host "Built $zip"
