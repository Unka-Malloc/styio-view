param([string]$Destination = "$env:LOCALAPPDATA\Programs\Vityo-Nightly")
$shortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Vityo Nightly.lnk"
if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut -Force }
if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
