param([string]$Destination = "$env:LOCALAPPDATA\Programs\Vityo-Nightly")
$ErrorActionPreference = "Stop"
$shortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Vityo Nightly.lnk"
if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut -Force }
if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
Write-Output "Vityo application components were removed. Per-user workspaces and durable state were retained."
