param([string]$Source = $PSScriptRoot, [string]$Destination = "$env:LOCALAPPDATA\Programs\Vityo-Nightly")
$resolvedSource = (Resolve-Path -LiteralPath $Source).Path
if (-not (Test-Path -LiteralPath "$resolvedSource\vityo_app.exe")) { throw "vityo_app.exe is missing from $resolvedSource" }
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Copy-Item -Path "$resolvedSource\*" -Destination $Destination -Recurse -Force
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Vityo Nightly.lnk")
$shortcut.TargetPath = "$Destination\vityo_app.exe"
$shortcut.WorkingDirectory = $Destination
$shortcut.Save()
Write-Output $Destination
