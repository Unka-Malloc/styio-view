param([string]$Source = $PSScriptRoot, [string]$Destination = "$env:LOCALAPPDATA\Programs\Styio-IDE-Nightly")
$resolvedSource = (Resolve-Path -LiteralPath $Source).Path
if (-not (Test-Path -LiteralPath "$resolvedSource\styio_ide.exe")) { throw "styio_ide.exe is missing from $resolvedSource" }
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Copy-Item -Path "$resolvedSource\*" -Destination $Destination -Recurse -Force
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Styio IDE Nightly.lnk")
$shortcut.TargetPath = "$Destination\styio_ide.exe"
$shortcut.WorkingDirectory = $Destination
$shortcut.Save()
Write-Output $Destination
