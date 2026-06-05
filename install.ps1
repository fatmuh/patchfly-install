# Patchfly CLI installer for Windows (PowerShell).
#
# Usage (R2/S3):
#   $env:PATCHFLY_BINARY_URL = "https://pub-xxx.r2.dev"
#   iwr -UseBasicParsing 'https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.ps1'|iex
#
# Environment variables:
#   $env:PATCHFLY_BINARY_URL   Base URL of the S3/R2 public bucket (REQUIRED)
#   $env:PATCHFLY_VERSION      Version to install (default: latest)
#   $env:PATCHFLY_INSTALL      Install location (default: $env:USERPROFILE\.patchfly\bin)

$ErrorActionPreference = 'Stop'

$BinaryName = 'patchfly.exe'
$InstallDir = if ($env:PATCHFLY_INSTALL) { $env:PATCHFLY_INSTALL } else { Join-Path $env:USERPROFILE '.patchfly\bin' }
$Version = if ($env:PATCHFLY_VERSION) { $env:PATCHFLY_VERSION } else { 'latest' }
$BinaryUrl = if ($env:PATCHFLY_BINARY_URL) { $env:PATCHFLY_BINARY_URL } else { '' }

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
function Info($msg)    { Write-Host "==> $msg" -ForegroundColor Cyan }
function Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg)    { Write-Host "(!) $msg" -ForegroundColor Yellow }
function Error($msg)   { Write-Host "[X] $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# Detect arch
# ---------------------------------------------------------------------------
$Arch = $env:PROCESSOR_ARCHITECTURE
switch ($Arch) {
  'AMD64' { $Arch = 'x64' }
  'ARM64' { $Arch = 'arm64' }
  default { Error "Unsupported arch: $Arch" }
}
$OS = 'windows'
$Asset = "patchfly-$OS-$Arch.exe"
Info "Detected: $OS / $Arch"

# ---------------------------------------------------------------------------
# Validate config
# ---------------------------------------------------------------------------
if (-not $BinaryUrl) {
  Error 'PATCHFLY_BINARY_URL is not set.'
  Write-Host ''
  Write-Host '  PATCHFLY_BINARY_URL should be the public URL of your S3/R2 bucket,' -ForegroundColor Gray
  Write-Host '  e.g. https://pub-xxxxxxxx.r2.dev or https://cdn.patchfly.dev' -ForegroundColor Gray
  Write-Host ''
  Write-Host 'Full example:' -ForegroundColor Gray
  Write-Host '  $env:PATCHFLY_BINARY_URL = "https://pub-xxxxxxxx.r2.dev"' -ForegroundColor Gray
  Write-Host '  iwr -UseBasicParsing https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.ps1 | iex' -ForegroundColor Gray
}
$BinaryUrl = $BinaryUrl.TrimEnd('/')

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------
$VersionPath = if ($Version -eq 'latest') { 'latest' } else { "v$Version" }
Success "Version: $VersionPath"

# ---------------------------------------------------------------------------
# Set up temp dir
# ---------------------------------------------------------------------------
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("patchfly-install-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Tmp | Out-Null

try {
  $DownloadUrl = "$BinaryUrl/cli/$VersionPath/$Asset"
  Info "Downloading: $DownloadUrl"

  $Target = Join-Path $Tmp $BinaryName
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $Target -UseBasicParsing -ErrorAction Stop
  } catch {
    $code = $_.Exception.Response.StatusCode.value__
    if (-not $code) { $code = 'unknown' }
    Error "Download failed (HTTP $code) for: $DownloadUrl"
  }

  if (-not (Test-Path $Target) -or (Get-Item $Target).Length -eq 0) {
    Error "Downloaded file is empty or missing: $DownloadUrl"
  }

  # Verify SHA-256 if available
  $ShaUrl = "$BinaryUrl/cli/$VersionPath/$Asset.sha256"
  $ShaFile = Join-Path $Tmp "$Asset.sha256"
  try {
    Invoke-WebRequest -Uri $ShaUrl -OutFile $ShaFile -UseBasicParsing -ErrorAction Stop
    if (Test-Path $ShaFile) {
      $expected = (Get-Content $ShaFile -First 1).Split(' ')[0].ToLower()
      $actual = (Get-FileHash -Algorithm SHA256 $Target).Hash.ToLower()
      if ($expected -eq $actual) {
        Success 'SHA-256 verified'
      } else {
        Warn "SHA-256 mismatch"
        Warn "  expected: $expected"
        Warn "  actual:   $actual"
      }
    }
  } catch {
    # SHA file not available — skip verification (not fatal)
  }

  $Size = [math]::Round((Get-Item $Target).Length / 1MB, 2)
  Success "Downloaded $Size MB"

  # ---------------------------------------------------------------------------
  # Install
  # ---------------------------------------------------------------------------
  if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  }
  $BinaryPath = Join-Path $InstallDir $BinaryName
  Move-Item -Force $Target $BinaryPath
  Success "Installed to: $BinaryPath"

  # ---------------------------------------------------------------------------
  # PATH setup
  # ---------------------------------------------------------------------------
  $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($currentPath -like "*$InstallDir*") {
    Success "Already in PATH - you can run: patchfly --version"
  } else {
    Warn 'Not in PATH yet. Adding to user PATH...'
    [Environment]::SetEnvironmentVariable('Path', "$currentPath;$InstallDir", 'User')
    $env:Path = "$env:Path;$InstallDir"
    Success "Added $InstallDir to user PATH (current shell updated; new shells will need restart)"

    Warn 'To persist for ALL new PowerShell windows, run this once:'
    Write-Host '  [Environment]::SetEnvironmentVariable("Path", $env:Path, "User")' -ForegroundColor DarkGray
  }

  Write-Host ''
  Info 'Verify installation:'
  Write-Host "  & '$BinaryPath' --version" -ForegroundColor DarkGray
  Write-Host ''
  Info 'Quick start:'
  Write-Host '  patchfly register --email you@example.com --password yourpass' -ForegroundColor DarkGray
  Write-Host '  patchfly apps create --slug com.example.app --name "My App"' -ForegroundColor DarkGray
  Write-Host '  patchfly patch' -ForegroundColor DarkGray
}
finally {
  if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
}
