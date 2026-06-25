param(
    [string]$Platforms,
    [switch]$WithAndroid,
    [switch]$SkipPlatformBootstrap,
    [switch]$SkipNpm,
    [switch]$SkipFlutterPub
)

$ErrorActionPreference = "Stop"

# Windows-native companion to bootstrap-workspace.sh. It resolves PowerShell
# friendly executable names before generating Flutter runners or restoring deps.
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$FlutterHome = if ($env:VITYO_FLUTTER_HOME) { $env:VITYO_FLUTTER_HOME } else { Join-Path $env:USERPROFILE "develop\\flutter" }

function Write-Log {
    param([string]$Message)
    Write-Host "[Vityo workspace] $Message"
}

function Add-Platform {
    param(
        [string]$PlatformList,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($PlatformList)) {
        return $Name
    }

    $items = $PlatformList.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($items -contains $Name) {
        return ($items -join ",")
    }

    return (($items + $Name) -join ",")
}

function Resolve-Executable {
    param(
        [string]$ConfiguredPath,
        [string[]]$CommandNames,
        [string]$MissingMessage
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        if (Test-Path -LiteralPath $ConfiguredPath) {
            return (Resolve-Path -LiteralPath $ConfiguredPath).Path
        }
        throw $MissingMessage
    }

    foreach ($name in $CommandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    throw $MissingMessage
}

function Resolve-FlutterBin {
    $configured = if ($env:VITYO_FLUTTER_BIN) { $env:VITYO_FLUTTER_BIN } else { $null }
    if (-not $configured) {
        $homeFlutter = Join-Path $FlutterHome "bin\\flutter.bat"
        if (Test-Path -LiteralPath $homeFlutter) {
            return (Resolve-Path -LiteralPath $homeFlutter).Path
        }
    }

    return Resolve-Executable `
        -ConfiguredPath $configured `
        -CommandNames @("flutter.bat", "flutter") `
        -MissingMessage "flutter is not installed. Set VITYO_FLUTTER_HOME, VITYO_FLUTTER_BIN, or add flutter to PATH."
}

function Resolve-NpmBin {
    $configured = if ($env:VITYO_NPM_BIN) { $env:VITYO_NPM_BIN } else { $null }
    return Resolve-Executable `
        -ConfiguredPath $configured `
        -CommandNames @("npm.cmd", "npm") `
        -MissingMessage "npm is not installed. Install Node.js or set VITYO_NPM_BIN."
}

function Invoke-AtPath {
    param(
        [string]$Path,
        [scriptblock]$ScriptBlock
    )

    Push-Location $Path
    try {
        & $ScriptBlock
    } finally {
        Pop-Location
    }
}

if ([string]::IsNullOrWhiteSpace($Platforms)) {
    $Platforms = "web,windows"
}

if ($WithAndroid) {
    $Platforms = Add-Platform -PlatformList $Platforms -Name "android"
}

$FlutterBin = $null
if (-not $SkipPlatformBootstrap -or -not $SkipFlutterPub) {
    $FlutterBin = Resolve-FlutterBin
}

if (-not $SkipPlatformBootstrap) {
    Write-Log "generating Flutter runners for platforms: $Platforms"
    Invoke-AtPath -Path (Join-Path $Root "frontend\\vityo_app") -ScriptBlock {
        & $FlutterBin create `
            --platforms="$Platforms" `
            --project-name=vityo_app `
            --org=io.vityo `
            .
    }
}

if (-not $SkipNpm) {
    Write-Log "installing prototype npm dependencies"
    $NpmBin = Resolve-NpmBin
    Invoke-AtPath -Path (Join-Path $Root "prototype") -ScriptBlock {
        & $NpmBin ci
    }
}

if (-not $SkipFlutterPub) {
    Write-Log "installing Flutter package dependencies"
    Invoke-AtPath -Path (Join-Path $Root "frontend\\vityo_app") -ScriptBlock {
        & $FlutterBin pub get
    }
}

Write-Log "workspace bootstrap complete"
