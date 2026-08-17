param(
  [string]$Source = $PSScriptRoot,
  [string]$Destination = "$env:LOCALAPPDATA\Programs\Vityo-Nightly"
)
$ErrorActionPreference = "Stop"
$resolvedSource = (Resolve-Path -LiteralPath $Source).Path
$app = Join-Path $resolvedSource "vityo_app.exe"
$daemon = Join-Path $resolvedSource "components\vityod.exe"
$componentManifest = Join-Path $resolvedSource "components\vityod-component.json"
if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { throw "Vityo application executable is missing" }
if (-not (Test-Path -LiteralPath $daemon -PathType Leaf)) { throw "Packaged vityod component is missing" }
if (-not (Test-Path -LiteralPath $componentManifest -PathType Leaf)) { throw "Packaged vityod manifest is missing" }
$identity = Get-Content -LiteralPath $componentManifest -Raw | ConvertFrom-Json
if ($identity.component -ne "vityod" -or $identity.target -ne "x86_64-pc-windows-msvc" -or $identity.package_relative_path -ne "components/vityod.exe") {
  throw "Packaged vityod identity does not match the Windows lane"
}
$digest = (Get-FileHash -LiteralPath $daemon -Algorithm SHA256).Hash.ToLowerInvariant()
if ($identity.executable_sha256 -ne $digest) { throw "Packaged vityod digest does not match its manifest" }
$health = & $daemon --health | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $health.component -ne "vityod" -or $health.status -ne "ready" -or $health.protocolVersion -ne 1) {
  throw "Packaged vityod health check failed"
}

$destinationParent = Split-Path -Parent $Destination
New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
$staging = Join-Path $destinationParent "Vityo-Nightly.installing"
$backup = Join-Path $destinationParent "Vityo-Nightly.rollback"
if ((Test-Path -LiteralPath $staging) -or (Test-Path -LiteralPath $backup)) {
  throw "A previous Vityo install transaction requires recovery"
}
$previousMoved = $false
$candidateActivated = $false
try {
  New-Item -ItemType Directory -Path $staging | Out-Null
  Copy-Item -Path "$resolvedSource\*" -Destination $staging -Recurse
  if (Test-Path -LiteralPath $Destination) {
    Move-Item -LiteralPath $Destination -Destination $backup
    $previousMoved = $true
  }
  Move-Item -LiteralPath $staging -Destination $Destination
  $candidateActivated = $true
  $installedHealth = & (Join-Path $Destination "components\vityod.exe") --health | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0 -or $installedHealth.status -ne "ready") {
    throw "Installed vityod health check failed"
  }
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Vityo Nightly.lnk")
  $shortcut.TargetPath = Join-Path $Destination "vityo_app.exe"
  $shortcut.WorkingDirectory = $Destination
  $shortcut.Save()
  if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
} catch {
  if ($candidateActivated -and (Test-Path -LiteralPath $Destination)) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
  }
  if ($previousMoved -and (Test-Path -LiteralPath $backup)) {
    Move-Item -LiteralPath $backup -Destination $Destination
  }
  if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
  throw
}
Write-Output $Destination
