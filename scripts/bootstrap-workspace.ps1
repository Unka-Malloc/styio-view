param(
    [string]$Platforms,
    [switch]$WithAndroid,
    [switch]$SkipPlatformBootstrap,
    [switch]$SkipNpm,
    [switch]$SkipFlutterPub
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$FlutterHome = if ($env:VITYO_FLUTTER_HOME) { $env:VITYO_FLUTTER_HOME } else { Join-Path $env:USERPROFILE "develop\\flutter" }
$FlutterBin = if ($env:VITYO_FLUTTER_BIN) { $env:VITYO_FLUTTER_BIN } else { Join-Path $FlutterHome "bin\\flutter.bat" }

function Write-Log {
    param([string]$Message)
    Write-Host "[Vityo workspace] $Message"
}

function Ensure-Platform {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Platforms)) {
        $Platforms = $Name
        return
    }

    $items = $Platforms.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($items -notcontains $Name) {
        $Platforms = ($items + $Name) -join ","
    }
}

if ([string]::IsNullOrWhiteSpace($Platforms)) {
    $Platforms = "web,windows"
}

if ($WithAndroid) {
    Ensure-Platform "android"
}

if (-not (Test-Path $FlutterBin)) {
    throw "flutter is not installed. Set VITYO_FLUTTER_HOME or VITYO_FLUTTER_BIN."
}

if (-not $SkipPlatformBootstrap) {
    Write-Log "generating Flutter runners for platforms: $Platforms"
    Push-Location (Join-Path $Root "frontend\\vityo_app")
    & $FlutterBin create `
        --platforms="$Platforms" `
        --project-name=vityo_app `
        --org=io.vityo `
        .
    Pop-Location
}

if (-not $SkipNpm) {
    Write-Log "installing prototype npm dependencies"
    Push-Location (Join-Path $Root "prototype")
    npm ci
    Pop-Location
}

if (-not $SkipFlutterPub) {
    Write-Log "installing Flutter package dependencies"
    Push-Location (Join-Path $Root "frontend\\vityo_app")
    & $FlutterBin pub get
    Pop-Location
}

Write-Log "workspace bootstrap complete"
