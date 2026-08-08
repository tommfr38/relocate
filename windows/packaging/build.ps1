# Build Relocate.exe and the Windows installer.
#
#   powershell -ExecutionPolicy Bypass -File packaging\build.ps1
#
# Must be run on Windows: PyInstaller produces a binary for the OS it runs on, so a
# Windows .exe cannot be cross-built from macOS or Linux.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "==> Creating virtual environment" -ForegroundColor Cyan
if (-not (Test-Path ".venv")) { python -m venv .venv }
$py = Join-Path $root ".venv\Scripts\python.exe"

Write-Host "==> Installing dependencies" -ForegroundColor Cyan
& $py -m pip install --upgrade pip
& $py -m pip install -r requirements.txt pyinstaller

Write-Host "==> Running tests" -ForegroundColor Cyan
& $py -m pytest tests -q
if ($LASTEXITCODE -ne 0) { throw "tests failed" }

Write-Host "==> Building executable" -ForegroundColor Cyan
Remove-Item -Recurse -Force build, dist -ErrorAction SilentlyContinue
& $py -m PyInstaller packaging\Relocate.spec --noconfirm
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed" }

Write-Host "==> Building installer" -ForegroundColor Cyan
$iscc = Get-Command iscc -ErrorAction SilentlyContinue
if ($null -eq $iscc) {
    $candidate = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (Test-Path $candidate) { $iscc = $candidate } else { $iscc = $null }
} else {
    $iscc = $iscc.Source
}

if ($null -eq $iscc) {
    Write-Warning "Inno Setup (iscc) not found - skipping installer."
    Write-Host "The unpackaged app is in dist\Relocate\" -ForegroundColor Green
} else {
    & $iscc packaging\installer.iss
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
    Write-Host "==> Installer written to dist\" -ForegroundColor Green
}
