param(
    [switch]$WithAndroid,
    [string]$AndroidProfiles = $(if ($env:VITYO_ANDROID_PROFILES) { $env:VITYO_ANDROID_PROFILES } else { "android-35,android-36" }),
    [string]$AndroidDefaultProfile = $(if ($env:VITYO_ANDROID_DEFAULT_PROFILE) { $env:VITYO_ANDROID_DEFAULT_PROFILE } else { "android-36" }),
    [switch]$SkipWorkspaceBootstrap
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PythonStandardVersion = (Get-Content -Raw (Join-Path $Root ".python-version")).Trim()
$NodeStandardVersion = (Get-Content -Raw (Join-Path $Root ".nvmrc")).Trim()
$FlutterStandardVersion = (Get-Content -Raw (Join-Path $Root ".flutter-version")).Trim()
$ChromiumStandardVersion = (Get-Content -Raw (Join-Path $Root ".chromium-version")).Trim()
$DartStandardVersion = "3.11.5"
$CmakeStandardVersion = "3.31.6"
$AndroidCmdlineToolsVersion = "14742923"
$AndroidProfileFile = if ($env:VITYO_ANDROID_PROFILE_FILE) { $env:VITYO_ANDROID_PROFILE_FILE } else { Join-Path $Root "toolchain\android-sdk-profiles.csv" }
$FlutterHome = if ($env:VITYO_FLUTTER_HOME) { $env:VITYO_FLUTTER_HOME } else { Join-Path $env:USERPROFILE "develop\\flutter" }
$AndroidSdkRoot = if ($env:VITYO_ANDROID_SDK_ROOT) { $env:VITYO_ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA "Android\\Sdk" }
$NodeInstallRoot = if ($env:VITYO_NODE_INSTALL_ROOT) { $env:VITYO_NODE_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "Vityo\\nodejs" }
$BrowserHome = if ($env:VITYO_BROWSER_HOME) { $env:VITYO_BROWSER_HOME } else { Join-Path $env:LOCALAPPDATA "Vityo\\browser" }
$ToolVenv = if ($env:VITYO_TOOL_VENV) { $env:VITYO_TOOL_VENV } else { Join-Path $env:LOCALAPPDATA "Vityo\\tools" }

function Write-Log {
    param([string]$Message)
    Write-Host "[Vityo windows env] $Message"
}

function Require-Windows {
    if ($env:OS -ne "Windows_NT") {
        throw "This script only supports Windows."
    }
}

function Require-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is required on Windows hosts."
    }
}

function Download-File {
    param(
        [string]$Url,
        [string]$Destination
    )
    Ensure-Directory (Split-Path -Parent $Destination)
    $lastError = $null
    $maxAttempts = 20
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt += 1) {
        try {
            if (($attempt -eq 1) -and (Test-Path $Destination)) {
                Remove-Item -Force $Destination
            }
            $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
            if ($curl) {
                $curlArgs = @("--fail", "--location", "--retry", "10", "--retry-delay", "2", "--retry-all-errors")
                if ((Test-Path $Destination) -and ((Get-Item $Destination).Length -gt 0)) {
                    $curlArgs += @("--continue-at", "-")
                }
                $curlArgs += @("--output", $Destination, $Url)
                & $curl.Source @curlArgs
                if ($LASTEXITCODE -ne 0) {
                    throw "curl.exe exited with code $LASTEXITCODE"
                }
            } else {
                Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
            }

            if ((Test-Path $Destination) -and ((Get-Item $Destination).Length -gt 0)) {
                return
            }
            throw "downloaded file is empty"
        } catch {
            $lastError = $_
            if ($attempt -eq $maxAttempts) {
                throw "Failed to download $Url after $attempt attempts: $lastError"
            }
            Start-Sleep -Seconds ([Math]::Min(30, 2 * $attempt))
        }
    }
}

function New-TempDownloadPath {
    param([string]$FileName)
    return Join-Path $env:TEMP "vityo-$PID-$FileName"
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-NodeWindowsArchitecture {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") {
        return "arm64"
    }
    return "x64"
}

function Add-ToUserPath {
    param([string]$Entry)

    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($current) {
        $parts = $current.Split(";") | Where-Object { $_ }
    }
    if ($parts -notcontains $Entry) {
        $updated = ($parts + $Entry) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $updated, "User")
    }
}

function Install-Python {
    $current = ""
    try {
        $current = (& py -3.13 --version) -replace '^Python\s+', ''
    } catch {
        $current = ""
    }
    if ($current -eq $PythonStandardVersion) {
        Write-Log "Python already matches standardized version $current"
        return
    }

    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "amd64" }
    $installer = "python-$PythonStandardVersion-$arch.exe"
    $url = "https://www.python.org/ftp/python/$PythonStandardVersion/$installer"
    $tmp = New-TempDownloadPath $installer
    Write-Log "Installing Python $PythonStandardVersion"
    Download-File -Url $url -Destination $tmp
    Start-Process -FilePath $tmp -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1" -Wait
}

function Install-ToolVenv {
    $pythonExe = Join-Path $ToolVenv "Scripts\\python.exe"
    Write-Log "Installing standardized CMake/CTest into $ToolVenv"
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3.13 -m venv $ToolVenv
    } else {
        throw "Python 3.13 launcher was not found after installation."
    }
    & $pythonExe -m pip install --upgrade pip
    & $pythonExe -m pip install "cmake==$CmakeStandardVersion"
}

function Install-WingetPackages {
    Write-Log "Installing Git, Visual Studio build tools, LLVM, and OpenJDK"
    winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements
    winget install --id LLVM.LLVM --silent --accept-package-agreements --accept-source-agreements
    winget install --id Microsoft.OpenJDK.21 --silent --accept-package-agreements --accept-source-agreements
    winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements --override "--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
}

function Install-Node {
    $nodeArch = Get-NodeWindowsArchitecture
    $nodeRoot = Join-Path $NodeInstallRoot "node-v$NodeStandardVersion-win-$nodeArch"
    $nodeExe = Join-Path $nodeRoot "node.exe"
    if ((Test-Path $nodeExe) -and ((& $nodeExe --version) -eq "v$NodeStandardVersion")) {
        Write-Log "Node.js already matches standardized version v$NodeStandardVersion"
        return
    }

    Ensure-Directory $NodeInstallRoot
    $archive = "node-v$NodeStandardVersion-win-$nodeArch.zip"
    $url = "https://nodejs.org/dist/v$NodeStandardVersion/$archive"
    $tmp = New-TempDownloadPath $archive
    Write-Log "Installing Node.js v$NodeStandardVersion"
    Download-File -Url $url -Destination $tmp
    if (Test-Path $nodeRoot) {
        Remove-Item -Recurse -Force $nodeRoot
    }
    Expand-Archive -Path $tmp -DestinationPath $NodeInstallRoot -Force
}

function Install-Flutter {
    $flutterBin = Join-Path $FlutterHome "bin\\flutter.bat"
    $versionJson = Join-Path $FlutterHome "bin\\cache\\flutter.version.json"
    $current = ""
    if (Test-Path $versionJson) {
        try {
            $current = (Get-Content -Raw $versionJson | ConvertFrom-Json).frameworkVersion
        } catch {
            $current = ""
        }
    }
    if ((-not $current) -and (Test-Path $flutterBin)) {
        try {
            $current = ((& $flutterBin --version --machine) | ConvertFrom-Json).frameworkVersion
        } catch {
            $current = ""
        }
    }
    if ($current -eq $FlutterStandardVersion) {
        Write-Log "Flutter already matches standardized version $FlutterStandardVersion"
        return
    }

    Ensure-Directory (Split-Path -Parent $FlutterHome)
    $archive = "flutter_windows_$FlutterStandardVersion-stable.zip"
    $url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/$archive"
    $tmp = New-TempDownloadPath $archive
    Write-Log "Installing Flutter $FlutterStandardVersion"
    Download-File -Url $url -Destination $tmp
    if (Test-Path $FlutterHome) {
        Remove-Item -Recurse -Force $FlutterHome
    }
    Expand-Archive -Path $tmp -DestinationPath (Split-Path -Parent $FlutterHome) -Force
}

function Install-ManagedBrowser {
    $chromeRoot = Join-Path $BrowserHome "chrome-win64"
    $chromeExe = Join-Path $chromeRoot "chrome.exe"
    $chromeManifest = Join-Path $chromeRoot "$ChromiumStandardVersion.manifest"
    $chromeVersion = ""
    if (Test-Path $chromeExe) {
        $chromeVersion = (Get-Item $chromeExe).VersionInfo.ProductVersion
    }
    if ((Test-Path $chromeExe) -and (($chromeVersion -eq $ChromiumStandardVersion) -or (Test-Path $chromeManifest))) {
        Write-Log "managed browser already matches standardized version $ChromiumStandardVersion"
        return
    }

    Ensure-Directory $BrowserHome
    $archive = "chrome-win64.zip"
    $url = "https://storage.googleapis.com/chrome-for-testing-public/$ChromiumStandardVersion/win64/$archive"
    $tmp = New-TempDownloadPath $archive
    Write-Log "Installing managed browser runtime $ChromiumStandardVersion"
    Download-File -Url $url -Destination $tmp
    if (Test-Path $chromeRoot) {
        Remove-Item -Recurse -Force $chromeRoot
    }
    Expand-Archive -Path $tmp -DestinationPath $BrowserHome -Force
}

function Install-AndroidSdk {
    $archive = "commandlinetools-win-$AndroidCmdlineToolsVersion`_latest.zip"
    $url = "https://dl.google.com/android/repository/$archive"
    $tmp = New-TempDownloadPath $archive
    $cmdlineRoot = Join-Path $AndroidSdkRoot "cmdline-tools\\latest"
    $sdkManager = Join-Path $cmdlineRoot "bin\\sdkmanager.bat"

    if (-not (Test-Path $sdkManager)) {
        Write-Log "Installing Android command-line tools"
        Ensure-Directory $AndroidSdkRoot
        Download-File -Url $url -Destination $tmp
        $extract = Join-Path $env:TEMP "Vityo-android-tools"
        if (Test-Path $extract) {
            Remove-Item -Recurse -Force $extract
        }
        Expand-Archive -Path $tmp -DestinationPath $extract -Force
        if (Test-Path $cmdlineRoot) {
            Remove-Item -Recurse -Force $cmdlineRoot
        }
        Ensure-Directory (Split-Path -Parent $cmdlineRoot)
        Move-Item (Join-Path $extract "cmdline-tools") $cmdlineRoot
    }

    $env:JAVA_HOME = (Get-ChildItem "C:\Program Files\Microsoft\jdk-21*" -Directory | Select-Object -First 1).FullName
    $env:ANDROID_HOME = $AndroidSdkRoot
    $nodeArch = Get-NodeWindowsArchitecture
    $env:Path = "$ToolVenv\Scripts;$NodeInstallRoot\node-v$NodeStandardVersion-win-$nodeArch;$FlutterHome\bin;$AndroidSdkRoot\cmdline-tools\latest\bin;$AndroidSdkRoot\platform-tools;$env:Path"

    & "$FlutterHome\bin\flutter.bat" config --android-sdk $AndroidSdkRoot --enable-web --enable-windows-desktop --enable-android
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\android-sdk-profile.ps1") install --profiles $AndroidProfiles --sdk-root $AndroidSdkRoot
}

function Write-UserEnv {
    $chromePath = Join-Path $BrowserHome "chrome-win64\\chrome.exe"
    $nodeArch = Get-NodeWindowsArchitecture
    [Environment]::SetEnvironmentVariable("FLUTTER_HOME", $FlutterHome, "User")
    [Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $AndroidSdkRoot, "User")
    [Environment]::SetEnvironmentVariable("ANDROID_HOME", $AndroidSdkRoot, "User")
    [Environment]::SetEnvironmentVariable("STYIO_CHROME_PATH", $chromePath, "User")
    [Environment]::SetEnvironmentVariable("CHROME_EXECUTABLE", $chromePath, "User")
    [Environment]::SetEnvironmentVariable("VITYO_ANDROID_PROFILE_FILE", $AndroidProfileFile, "User")
    [Environment]::SetEnvironmentVariable("VITYO_ANDROID_PROFILES", $AndroidProfiles, "User")
    [Environment]::SetEnvironmentVariable("VITYO_ANDROID_DEFAULT_PROFILE", $AndroidDefaultProfile, "User")

    Add-ToUserPath (Join-Path $ToolVenv "Scripts")
    Add-ToUserPath (Join-Path $NodeInstallRoot "node-v$NodeStandardVersion-win-$nodeArch")
    Add-ToUserPath (Join-Path $FlutterHome "bin")
    if ($WithAndroid) {
        Add-ToUserPath (Join-Path $AndroidSdkRoot "cmdline-tools\\latest\\bin")
        Add-ToUserPath (Join-Path $AndroidSdkRoot "platform-tools")
    }
}

function Bootstrap-Workspace {
    Push-Location $Root
    try {
        if ($WithAndroid) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\bootstrap-workspace.ps1" -Platforms "web,windows,android"
        } else {
            & powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\bootstrap-workspace.ps1" -Platforms "web,windows"
        }
    } finally {
        Pop-Location
    }
}

Require-Windows
Require-Winget
Install-Python
Install-ToolVenv
Install-WingetPackages
Install-Node
Install-Flutter
Install-ManagedBrowser

if ($WithAndroid) {
    Install-AndroidSdk
} else {
    & "$FlutterHome\bin\flutter.bat" config --enable-web --enable-windows-desktop | Out-Null
}

Write-UserEnv

if (-not $SkipWorkspaceBootstrap) {
    Bootstrap-Workspace
}

$profileName = if ($WithAndroid) { "windows+android" } else { "windows" }
$chromePath = Join-Path $BrowserHome "chrome-win64\\chrome.exe"

Write-Host ""
Write-Host "Vityo Windows bootstrap complete."
Write-Host ""
Write-Host "Profile:         $profileName"
Write-Host "Python:          $PythonStandardVersion"
Write-Host "Node.js:         v$NodeStandardVersion"
Write-Host "Flutter/Dart:    $FlutterStandardVersion / $DartStandardVersion"
Write-Host "Browser runtime: $ChromiumStandardVersion"
if ($WithAndroid) {
    Write-Host "Android SDKs:    $AndroidProfiles (default: $AndroidDefaultProfile)"
}
Write-Host ""
Write-Host "Environment variables were written to the current user profile."
Write-Host "Open a new terminal before using flutter/node/cmake from PATH."
Write-Host ""
Write-Host "Typical next steps:"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\\scripts\\bootstrap-workspace.ps1 -Platforms web,windows$(if ($WithAndroid) { ',android' })"
if ($WithAndroid) {
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\\scripts\\android-sdk-profile.ps1 list"
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\\scripts\\android-sdk-profile.ps1 env $AndroidDefaultProfile"
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\\scripts\\android-sdk-profile.ps1 build --profiles $AndroidProfiles --parallel --artifact apk --mode debug"
}
Write-Host "  cd frontend\\vityo_app; flutter analyze; flutter test"
Write-Host "  cd prototype; `$env:STYIO_CHROME_PATH = '$chromePath'; `$env:STYIO_EDITOR_URL = 'http://127.0.0.1:4180/editor'; npm run selftest:editor"
