# Build Relocate.exe and the Windows installer.
#
#   powershell -ExecutionPolicy Bypass -File packaging\build.ps1
#
# Must be run on Windows: PyInstaller produces a binary for the OS it runs on, so a
# Windows .exe cannot be cross-built from macOS or Linux.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# pymobiledevice3 pulls in pyimg4 -> lzfse and pylzss, C extensions that publish no
# wheels past CPython 3.12. On a newer interpreter pip falls back to building them from
# source and fails on any machine without MSVC, so pick a supported interpreter rather
# than whatever "python" happens to be.
$supported = @("3.12", "3.11", "3.10")

Write-Host "==> Selecting Python interpreter" -ForegroundColor Cyan
$baseExe = $null
$baseArgs = @()
$launcher = Get-Command py -ErrorAction SilentlyContinue
foreach ($version in $supported) {
    if ($null -ne $launcher) {
        & py "-$version" -c "pass" 2>$null
        if ($LASTEXITCODE -eq 0) { $baseExe = "py"; $baseArgs = @("-$version"); break }
    }
    $candidate = "$env:LOCALAPPDATA\Programs\Python\Python$($version -replace '\.','')\python.exe"
    if (Test-Path $candidate) { $baseExe = $candidate; break }
}
if ($null -eq $baseExe) {
    throw "No supported Python found. Install one of: $($supported -join ', ') (e.g. winget install Python.Python.3.12)"
}
Write-Host "    using $baseExe $baseArgs" -ForegroundColor DarkGray

Write-Host "==> Creating virtual environment" -ForegroundColor Cyan
$py = Join-Path $root ".venv\Scripts\python.exe"
# A .venv left over from an unsupported interpreter would reintroduce the failure.
if ((Test-Path ".venv") -and (Test-Path $py)) {
    $existing = & $py -c "import sys; print('{}.{}'.format(*sys.version_info[:2]))" 2>$null
    if ($LASTEXITCODE -ne 0 -or $supported -notcontains $existing) {
        Write-Host "    discarding .venv built on unsupported Python $existing" -ForegroundColor DarkGray
        Remove-Item -Recurse -Force .venv
    }
}
if (-not (Test-Path $py)) {
    Remove-Item -Recurse -Force .venv -ErrorAction SilentlyContinue
    & $baseExe @baseArgs -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw "failed to create virtual environment" }
}

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
$command = Get-Command iscc -ErrorAction SilentlyContinue
if ($null -ne $command) {
    $iscc = $command.Source
} else {
    # Inno Setup is not added to PATH, and winget installs it per-user rather than
    # under Program Files, so check every location it plausibly lands in.
    $iscc = $null
    foreach ($candidate in @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )) {
        if (Test-Path $candidate) { $iscc = $candidate; break }
    }
}

if ($null -eq $iscc) {
    Write-Warning "Inno Setup (iscc) not found - skipping installer."
    Write-Host "The unpackaged app is in dist\Relocate\" -ForegroundColor Green
} else {
    & $iscc packaging\installer.iss
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
    Write-Host "==> Installer written to dist\" -ForegroundColor Green
}
