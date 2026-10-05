# Builds the browser (Web) version of Last Epoch Builder, published to GitHub Pages by .github/workflows/pages.yml.
# Usage: .\build_web.ps1 [-Godot <path to Godot 4.7 console exe>]
# Godot is taken from -Godot, else from the GODOT environment variable, else from "godot" on PATH.
# Needs the Godot 4.7 export templates (web_nothreads_release.zip) and Python 3 ("python" on PATH; it minifies the
# packed copy of research/data). Output: build/web (index.html + files).
# Test locally: python -m http.server -d build/web 8060, then open http://localhost:8060
param(
    [string]$Godot = $env:GODOT
)
$ErrorActionPreference = "Stop"
if (-not $Godot) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Godot 4.7 not found: pass -Godot <console exe> or set the GODOT environment variable." }
    $Godot = $cmd.Source
}
$root = $PSScriptRoot
$client = Join-Path $root "client"
$dataCopy = Join-Path $client "data/research"
$out = Join-Path $root "build/web"

# The client reads research/data from the repository in the editor; the export packs a copy (LE.research_dir).
if (Test-Path $dataCopy) { Remove-Item -Recurse -Force $dataCopy }
Copy-Item -Recurse (Join-Path $root "research/data") $dataCopy
# The page downloads the whole pack: drop the indentation of the JSON copy (about a fifth of its size).
python -c "import json, pathlib, sys; [p.write_text(json.dumps(json.loads(p.read_text(encoding='utf-8')), ensure_ascii=False, separators=(',', ':')), encoding='utf-8') for p in pathlib.Path(sys.argv[1]).rglob('*.json')]" $dataCopy
if ($LASTEXITCODE -ne 0) { throw "JSON minification failed ($LASTEXITCODE)" }
try {
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    New-Item -ItemType Directory -Force $out | Out-Null
    & $Godot --headless --path $client --import | Out-Null
    & $Godot --headless --path $client --export-release "Web" (Join-Path $out "index.html")
    if ($LASTEXITCODE -ne 0) { throw "Godot export failed ($LASTEXITCODE)" }
}
finally {
    Remove-Item -Recurse -Force $dataCopy
}
Write-Host "Built $out"
