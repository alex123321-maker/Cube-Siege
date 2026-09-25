[CmdletBinding()]
param(
    [string]$InstallRoot = $(if (Test-Path 'D:\') { 'D:\ProgramFiles\cube-siege-art-tools' } else { Join-Path $env:LOCALAPPDATA 'CubeSiege\tools' })
)

$ErrorActionPreference = 'Stop'
$version = '5.2.1'
$archiveName = "blender-$version-windows-x64.zip"
$expectedSha256 = '0e631dad7d0cad6d5d18abdd2e2550f6c0213215334eda00ddbd3d22b96ecb2c'
$downloadUrl = "https://download.blender.org/release/Blender5.2/$archiveName"
$archivePath = Join-Path $InstallRoot $archiveName
$binaryPath = Join-Path $InstallRoot "blender-$version-windows-x64\blender.exe"

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
if (-not (Test-Path -LiteralPath $archivePath)) {
    Write-Host "Downloading official Blender $version LTS portable archive..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath
}
$actualSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -ne $expectedSha256) {
    throw "Blender archive checksum mismatch. Expected $expectedSha256, got $actualSha256"
}
if (-not (Test-Path -LiteralPath $binaryPath)) {
    Expand-Archive -LiteralPath $archivePath -DestinationPath $InstallRoot -Force
}
& $binaryPath --background --version
if ($LASTEXITCODE -ne 0) {
    throw "Blender headless validation failed with exit code $LASTEXITCODE"
}
Write-Host "Blender ready: $binaryPath"
Write-Host "For this shell: `$env:BLENDER_BIN='$binaryPath'"
