param(
    [string]$Platforms,
    [switch]$WithAndroid,
    [switch]$SkipPlatformBootstrap,
    [switch]$SkipNpm,
    [switch]$SkipFlutterPub
)

$ErrorActionPreference = "Stop"

# Windows-native companion to bootstrap-workspace.sh. It resolves PowerShell
# friendly executable names, preserves tracked Flutter state after runner
# generation, and prepares plugin junctions when symlinks are unavailable.
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

function Test-PlatformEnabled {
    param(
        [string]$PlatformList,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($PlatformList)) {
        return $false
    }

    $items = $PlatformList.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return $items -contains $Name
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

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-FileSnapshot {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return [System.IO.File]::ReadAllText($Path)
    }
    return $null
}

function Restore-FileSnapshot {
    param(
        [string]$Path,
        [AllowNull()][string]$Content
    )
    if ($null -ne $Content) {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    }
}

function Ensure-WindowsPluginJunctions {
    param([string]$AppRoot)

    if ($env:OS -ne "Windows_NT") {
        return
    }

    $dependenciesPath = Join-Path $AppRoot ".flutter-plugins-dependencies"
    if (-not (Test-Path -LiteralPath $dependenciesPath)) {
        return
    }

    $dependencies = Get-Content -Raw -LiteralPath $dependenciesPath | ConvertFrom-Json
    $platforms = @(
        @{ Name = "Windows"; Plugins = @($dependencies.plugins.windows); Root = Join-Path $AppRoot "windows\\flutter\\ephemeral\\.plugin_symlinks" },
        @{ Name = "Linux"; Plugins = @($dependencies.plugins.linux); Root = Join-Path $AppRoot "linux\\flutter\\ephemeral\\.plugin_symlinks" }
    )

    foreach ($platform in $platforms) {
        if ($platform.Plugins.Count -eq 0) {
            continue
        }

        $junctionRoot = $platform.Root
        Ensure-Directory $junctionRoot

        foreach ($plugin in $platform.Plugins) {
            $name = [string]$plugin.name
            $target = ([string]$plugin.path).TrimEnd([char[]]"\/")
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($target)) {
                continue
            }
            if (-not (Test-Path -LiteralPath $target)) {
                throw "Flutter $($platform.Name) plugin '$name' was restored to '$target', but that path does not exist."
            }

            $junction = Join-Path $junctionRoot $name
            if (Test-Path -LiteralPath $junction) {
                $item = Get-Item -Force -LiteralPath $junction
                if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                    throw "Expected '$junction' to be a junction or symlink. Remove it before bootstrapping Windows plugins."
                }
                cmd /c rmdir "$junction" | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to remove stale plugin junction '$junction'."
                }
            }

            cmd /c mklink /J "$junction" "$target" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create plugin junction '$junction' -> '$target'."
            }
        }
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
    $AppRoot = Join-Path $Root "frontend\\vityo_app"
    $metadataPath = Join-Path $AppRoot ".metadata"
    $metadataSnapshot = Read-FileSnapshot $metadataPath
    $defaultWidgetTest = Join-Path $AppRoot "test\\widget_test.dart"
    $hadDefaultWidgetTest = Test-Path -LiteralPath $defaultWidgetTest
    Invoke-AtPath -Path $AppRoot -ScriptBlock {
        & $FlutterBin create `
            --platforms="$Platforms" `
            --project-name=vityo_app `
            --org=io.vityo `
            .
    }
    Restore-FileSnapshot -Path $metadataPath -Content $metadataSnapshot
    if ((-not $hadDefaultWidgetTest) -and (Test-Path -LiteralPath $defaultWidgetTest)) {
        Remove-Item -Force -LiteralPath $defaultWidgetTest
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
    $AppRoot = Join-Path $Root "frontend\\vityo_app"
    $pubspecLock = Join-Path $AppRoot "pubspec.lock"
    $pubspecLockSnapshot = Read-FileSnapshot $pubspecLock
    Invoke-AtPath -Path $AppRoot -ScriptBlock {
        & $FlutterBin pub get
    }
    if (Test-PlatformEnabled -PlatformList $Platforms -Name "windows") {
        Write-Log "preparing Windows plugin junctions"
        Ensure-WindowsPluginJunctions -AppRoot $AppRoot
    }
    Restore-FileSnapshot -Path $pubspecLock -Content $pubspecLockSnapshot
}

Write-Log "workspace bootstrap complete"
