param(
    [string]$Profile,
    [string]$DeviceId,
    [ValidateSet("debug", "profile", "release")]
    [string]$Mode = "debug",
    [string]$FlutterDir,
    [string]$OutDir,
    [string]$WorkDir,
    [string]$PackageName = "io.vityo.app",
    [string]$TargetPlatform,
    [switch]$BuildOnly,
    [switch]$NoLaunch,
    [switch]$ListDevices,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraFlutterArgs
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $FlutterDir) { $FlutterDir = Join-Path $Root "frontend\vityo_app" }
if (-not $OutDir) { $OutDir = Join-Path $Root "build\android-device-verification" }
if (-not $WorkDir) { $WorkDir = Join-Path $Root "build\android-device-workspaces" }

function Write-Log {
    param([string]$Message)
    Write-Host "[verify-android-device] $Message"
}

function Fail {
    param([string]$Message)
    throw $Message
}

function Require-Adb {
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        Fail "adb is required."
    }
}

function Show-Usage {
    @'
Usage: verify-android-device.ps1 -Profile <name> [options]

Build, install, and optionally launch Vityo on a real Android device using
one of the standardized Android SDK profiles.

Options:
  -Profile <name>         Android profile from toolchain/android-sdk-profiles.csv
  -DeviceId <id>          adb device id; when omitted, a single connected device is auto-selected
  -Mode <debug|profile|release>
  -FlutterDir <dir>
  -OutDir <dir>
  -WorkDir <dir>
  -PackageName <name>
  -TargetPlatform <csv>
  -BuildOnly
  -NoLaunch
  -ListDevices
'@ | Write-Host
}

function Show-Devices {
    Require-Adb
    & adb devices -l
}

function Select-Device {
    $lines = & adb devices
    $devices = @()
    foreach ($line in $lines) {
        if ($line -match '^List of devices') { continue }
        if (-not $line.Trim()) { continue }
        $parts = $line -split '\s+'
        if ($parts.Count -ge 2 -and $parts[1] -eq 'device') {
            $devices += $parts[0]
        }
    }
    if ($devices.Count -eq 1) {
        return $devices[0]
    }
    if ($devices.Count -eq 0) {
        Fail "No authorized Android devices are connected."
    }
    Fail "Multiple Android devices are connected; pass -DeviceId explicitly."
}

function Find-Apk {
    param(
        [string]$ProfileName,
        [string]$BuildMode
    )
    $artifactRoot = Join-Path (Join-Path $OutDir $ProfileName) "outputs\flutter-apk"
    $candidate = Join-Path $artifactRoot "app-$BuildMode.apk"
    if (Test-Path $candidate) {
        return $candidate
    }
    $first = Get-ChildItem -Path $artifactRoot -Filter *.apk -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($first) {
        return $first.FullName
    }
    return $null
}

if ($ListDevices) {
    Show-Devices
    exit 0
}

if (-not $Profile) {
    Show-Usage
    Fail "-Profile is required."
}

Require-Adb
if (-not $DeviceId) {
    $DeviceId = Select-Device
}

$buildArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $Root "scripts\android-sdk-profile.ps1"),
    "build",
    "--profiles", $Profile,
    "--artifact", "apk",
    "--mode", $Mode,
    "--flutter-dir", $FlutterDir,
    "--out-dir", $OutDir,
    "--work-dir", $WorkDir
)
if ($TargetPlatform) {
    $buildArgs += @("--target-platform", $TargetPlatform)
}
if ($ExtraFlutterArgs.Count -gt 0) {
    $buildArgs += "--"
    $buildArgs += $ExtraFlutterArgs
}

Write-Log "building APK for profile $Profile"
& powershell @buildArgs

$apkPath = Find-Apk -ProfileName $Profile -BuildMode $Mode
if (-not $apkPath) {
    Fail "Unable to locate built APK for profile $Profile."
}

if ($BuildOnly) {
    Write-Log "build complete: $apkPath"
    exit 0
}

Write-Log "installing APK on device $DeviceId"
& adb -s $DeviceId install -r $apkPath

if (-not $NoLaunch) {
    Write-Log "launching package $PackageName on device $DeviceId"
    & adb -s $DeviceId shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
}

Write-Log "Android device verification deploy complete"
