# Patchfly CLI installer for Windows (PowerShell).
#
# Copyright (c) 2024 Shorebird Labs, Inc. and Patchfly contributors
# Licensed under MIT and Apache License, Version 2.0
#
# Original work by the Patchfly contributors; not derived from
# the upstream Shorebird installer. See LICENSE-MIT and
# LICENSE-APACHE in this repository for the full license texts.
#
# One-liner (no setup required):
#   iwr -UseBasicParsing 'https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.ps1'|iex
#
# Environment variables (all optional):
#   $env:PATCHFLY_BINARY_URL   Override default binary CDN URL
#                              default: https://cdn.patchfly.dev
#   $env:PATCHFLY_VERSION      Version to install (default: latest)
#   $env:PATCHFLY_INSTALL      Install location
#                              default: $env:USERPROFILE\.patchfly\bin

$ErrorActionPreference = 'Stop'

$BinaryName = 'patchfly.exe'
$InstallDir = if ($env:PATCHFLY_INSTALL) { $env:PATCHFLY_INSTALL } else { Join-Path $env:USERPROFILE '.patchfly\bin' }
$Version = if ($env:PATCHFLY_VERSION) { $env:PATCHFLY_VERSION } else { 'latest' }
# Default binary CDN (cdn.patchfly.dev fronts the cdn.patchfly.dev bucket).
# Override with $env:PATCHFLY_BINARY_URL=... to self-host.
$BinaryUrl = if ($env:PATCHFLY_BINARY_URL) { $env:PATCHFLY_BINARY_URL } else { 'https://cdn.patchfly.dev' }
$BinaryUrl = $BinaryUrl.TrimEnd('/')

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
  default { Error "Unsupported arch: $Arch. Supported: AMD64, ARM64." }
}
$OS = 'windows'
$Asset = "patchfly-$OS-$Arch.exe"
Info "Detected platform: $OS / $Arch"

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------
$VersionPath = if ($Version -eq 'latest') { 'latest' } else { "v$Version" }
Info "Version: $VersionPath"

# ---------------------------------------------------------------------------
# Set up temp dir
# ---------------------------------------------------------------------------
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("patchfly-install-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Tmp | Out-Null

try {
  $DownloadUrl = "$BinaryUrl/cli/$VersionPath/$Asset"
  Info "Downloading from: $BinaryUrl/cli/$VersionPath/$Asset"

  $Target = Join-Path $Tmp $BinaryName
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $Target -UseBasicParsing -ErrorAction Stop
  } catch {
    $code = $_.Exception.Response.StatusCode.value__
    if (-not $code) { $code = 'unknown' }
    Error "Download failed (HTTP $code) for: $DownloadUrl`n`n  Troubleshooting:`n    - Check your internet connection`n    - Verify the release exists at: ${BinaryUrl}/cli/${VersionPath}/`n    - Try a specific version: `$env:PATCHFLY_VERSION=0.1.0 ...`n    - Self-host? Set `$env:PATCHFLY_BINARY_URL=... to your own bucket"
  }

  if (-not (Test-Path $Target) -or (Get-Item $Target).Length -eq 0) {
    Error "Downloaded file is empty or missing: $DownloadUrl"
  }

  # ---------------------------------------------------------------------------
  # Verify SHA-256 (if sidecar exists)
  # ---------------------------------------------------------------------------
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
        Warn "SHA-256 mismatch (continuing anyway)"
      }
    }
  } catch {
    # SHA file not available - skip verification
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
    Success "Already in PATH - run: patchfly --version"
  } else {
    Warn "Not in PATH yet. Adding to user PATH..."
    [Environment]::SetEnvironmentVariable('Path', "$currentPath;$InstallDir", 'User')
    $env:Path = "$env:Path;$InstallDir"
    Success "Added $InstallDir to user PATH (current shell updated; new shells will need restart)"
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
