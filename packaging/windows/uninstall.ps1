param([string]$Destination = "$env:LOCALAPPDATA\Programs\Styio-IDE-Nightly")
$shortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Styio IDE Nightly.lnk"
if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut -Force }
if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
