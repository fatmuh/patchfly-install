# Patchfly CLI — Installer

One-line installer for the **Patchfly CLI** (macOS / Linux / Windows).

Binaries are hosted on **S3-compatible storage** (Cloudflare R2, AWS S3, Backblaze B2, MinIO — your choice). The source code stays in the private `fatmuh/patchfly` repo.

## Quick Install

### macOS / Linux

```bash
curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.sh -sSf | bash
```

### Windows (PowerShell)

```powershell
iwr -UseBasicParsing 'https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.ps1'|iex
```

> ✅ **No setup required** — default binary CDN is hardcoded. Override with `$env:PATCHFLY_BINARY_URL` (PowerShell) or `PATCHFLY_BINARY_URL` (bash) to self-host.

## What It Does

1. **Detect platform** — OS (Linux/macOS/Windows) and CPU arch (x64/arm64)
2. **Download binary** — from `${PATCHFLY_BINARY_URL}/cli/latest/patchfly-{os}-{arch}` (or `v{version}` for pinned)
3. **Verify SHA-256** — if `.sha256` sidecar exists at the same path
4. **Install** — to `~/.patchfly/bin/patchfly` (Unix) or `%USERPROFILE%\.patchfly\bin\patchfly.exe` (Windows)
5. **Add to PATH** — auto on Windows; prompts on Unix (shell detection)

## Binary URL Layout

The script expects this object layout in your S3/R2 bucket:

```
{BUCKET}/
├── cli/
│   ├── latest/                          ← always points to newest release
│   │   ├── patchfly-linux-x64
│   │   ├── patchfly-linux-x64.sha256
│   │   ├── patchfly-linux-arm64
│   │   ├── patchfly-linux-arm64.sha256
│   │   ├── patchfly-macos-x64
│   │   ├── patchfly-macos-x64.sha256
│   │   ├── patchfly-macos-arm64
│   │   ├── patchfly-macos-arm64.sha256
│   │   ├── patchfly-windows-x64.exe
│   │   └── patchfly-windows-x64.exe.sha256
│   └── v0.1.0/                          ← versioned (kept forever)
│       └── (same files)
```

`PATCHFLY_BINARY_URL` should be the **public base URL** to your bucket, e.g.:

| Provider | Public URL format |
|---|---|
| Cloudflare R2 (default r2.dev) | `https://pub-{accountid}.r2.dev` |
| Cloudflare R2 (custom domain) | `https://cdn.your-domain.com` |
| AWS S3 (website endpoint) | `https://{bucket}.s3-website-{region}.amazonaws.com` |
| AWS S3 (REST endpoint) | `https://{bucket}.s3.{region}.amazonaws.com` |
| Backblaze B2 | `https://f000.backblazeb2.com/file/{bucket}` |
| MinIO (self-hosted) | `https://minio.your-domain.com/{bucket}` |

## Environment Variables (all optional)

| Var | Default | Description |
|---|---|---|
| `PATCHFLY_BINARY_URL` | `https://is3.cloudhost.id/moccilabs/patchfly` | Override the binary CDN URL |
| `PATCHFLY_VERSION` | `latest` | Specific version to install (e.g. `0.1.0`) |
| `PATCHFLY_INSTALL` | `~/.patchfly/bin` | Install location |

## Examples

```bash
# Install latest (default CDN)
curl -sSf https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.sh | bash

# Install specific version
PATCHFLY_VERSION=0.1.0 curl -sSf https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.sh | bash

# Self-host (use your own S3/R2 bucket)
PATCHFLY_BINARY_URL="https://my-bucket.s3.region.amazonaws.com" curl -sSf https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.sh | bash

# Install to custom path
PATCHFLY_INSTALL=/usr/local/bin curl -sSf ... | bash

# Verify
patchfly --version
```

## Local Testing (without internet)

The install scripts always try downloading first. If that fails, they print a clear error message with setup hints. They do **not** fall back to building from source (this script is for end users, not developers).

For local dev builds, see [`fatmuh/patchfly` README → Local development](https://github.com/fatmuh/patchfly#local-development).

## After Install

```bash
patchfly --version
patchfly register --email you@example.com --password yourpass
patchfly apps create --slug com.example.app --name "My App"
patchfly patch
```

## How Releases Get Into Your Bucket

The release workflow at `fatmuh/patchfly/.github/workflows/release.yml` builds binaries on every `v*` tag push and uploads to your bucket. Setup:

1. Create an R2/S3 bucket (e.g. `patchfly-cli`)
2. Make it public-read (configure bucket policy + R2 public access)
3. Add AWS credentials as GitHub secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
4. Add GitHub **variables** (not secrets) at the repo level:
   - `S3_BUCKET` = `patchfly-cli`
   - `S3_ENDPOINT` = `https://<accountid>.r2.cloudflarestorage.com` (R2 only — leave empty for AWS S3)
   - `S3_REGION` = `auto` (R2) or `us-east-1` (AWS)
   - `S3_PUBLIC_URL` = `https://pub-xxx.r2.dev` (the URL end users use)
5. Push a tag: `git tag v0.1.0 && git push origin v0.1.0`
6. Binaries appear at `${S3_PUBLIC_URL}/cli/v0.1.0/...` within ~3-5 minutes

## Why S3/R2 Instead of GitHub Releases?

GitHub's `GITHUB_TOKEN` cannot write to a different repo than the one the workflow runs in. For our setup (private source + public binaries), that would require a Personal Access Token. S3-compatible storage avoids this entirely — the workflow uses standard AWS credentials and uploads to your own bucket.

**Source code stays 100% private** in `fatmuh/patchfly`. **Only binaries** (compiled executables, no source) are in the S3/R2 bucket.
