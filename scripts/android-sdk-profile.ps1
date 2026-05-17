param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ProfileFile = if ($env:VITYO_ANDROID_PROFILE_FILE) { $env:VITYO_ANDROID_PROFILE_FILE } else { Join-Path $Root "toolchain\android-sdk-profiles.csv" }
$AndroidSdkRoot = if ($env:VITYO_ANDROID_SDK_ROOT) { $env:VITYO_ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$FlutterHome = if ($env:VITYO_FLUTTER_HOME) { $env:VITYO_FLUTTER_HOME } else { Join-Path $env:USERPROFILE "develop\flutter" }
$FlutterBin = if ($env:VITYO_FLUTTER_BIN) { $env:VITYO_FLUTTER_BIN } else { Join-Path $FlutterHome "bin\flutter.bat" }
$FlutterDirDefault = Join-Path $Root "frontend\vityo_app"
$OutDirDefault = Join-Path $Root "build\android-profile-artifacts"
$WorkDirDefault = Join-Path $Root "build\android-profile-workspaces"

function Write-Log {
    param([string]$Message)
    Write-Host "[android-sdk-profile] $Message"
}

function Fail {
    param([string]$Message)
    throw $Message
}

function Show-Usage {
    @'
Usage: android-sdk-profile.ps1 <command> [options]

Manage standardized Android SDK profiles for Vityo on Windows hosts.

Commands:
  list
  install [--profiles <csv>] [--sdk-root <dir>]
  env [<profile>]
  run [<profile>] -- <command...>
  build [options] [-- <extra flutter args>]

Build options:
  --profiles <csv>         Comma-separated profile list
  --artifact <apk|appbundle>
  --mode <debug|profile|release>
  --parallel
  --flutter-dir <dir>
  --out-dir <dir>
  --work-dir <dir>
  --target-platform <csv>
'@ | Write-Host
}

function Get-Profiles {
    if (-not (Test-Path $ProfileFile)) {
        Fail "Android profile file is missing: $ProfileFile"
    }
    return Import-Csv -Path $ProfileFile
}

function Get-ProfileMap {
    $map = @{}
    foreach ($profile in Get-Profiles) {
        $map[$profile.name] = $profile
    }
    return $map
}

function Get-Profile {
    param([string]$Name)
    $map = Get-ProfileMap
    if (-not $map.ContainsKey($Name)) {
        Fail "Unknown Android profile: $Name"
    }
    return $map[$Name]
}

function Split-ProfileNames {
    param([string]$Csv)
    $map = Get-ProfileMap
    $names = @()
    if ([string]::IsNullOrWhiteSpace($Csv) -or $Csv -eq "all") {
        foreach ($profile in Get-Profiles) {
            $names += $profile.name
        }
        return $names
    }
    foreach ($raw in $Csv.Split(",")) {
        $name = $raw.Trim()
        if (-not $name) { continue }
        if (-not $map.ContainsKey($name)) {
            Fail "Unknown Android profile: $name"
        }
        $names += $name
    }
    if ($names.Count -eq 0) {
        Fail "No valid Android profiles selected."
    }
    return $names
}

function Get-DefaultProfileName {
    foreach ($profile in Get-Profiles) {
        if ($profile.default_profile -in @("yes", "true")) {
            return $profile.name
        }
    }
    return (Get-Profiles | Select-Object -Last 1).name
}

function Ensure-Flutter {
    if (-not (Test-Path $FlutterBin)) {
        Fail "flutter was not found at $FlutterBin"
    }
}

function Ensure-SdkManager {
    $sdkManager = Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
    if (-not (Test-Path $sdkManager)) {
        Fail "sdkmanager is missing under $AndroidSdkRoot. Run bootstrap-dev-env-windows.ps1 -WithAndroid first."
    }
    return $sdkManager
}

function Add-PathEntry {
    param(
        [string[]]$Entries,
        [string]$ExistingPath
    )
    $parts = @()
    if ($ExistingPath) {
        $parts = $ExistingPath.Split(";") | Where-Object { $_ }
    }
    foreach ($entry in $Entries) {
        if ($entry -and ($parts -notcontains $entry)) {
            $parts += $entry
        }
    }
    return ($parts -join ";")
}

function Get-JavaHome {
    if ($env:JAVA_HOME) {
        return $env:JAVA_HOME
    }
    $jdk = Get-ChildItem "C:\Program Files\Microsoft\jdk-21*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($jdk) {
        return $jdk.FullName
    }
    return $null
}

function Get-ProfileEnv {
    param([string]$ProfileName)
    $profile = Get-Profile $ProfileName
    $javaHome = Get-JavaHome
    $pathEntries = @(
        (Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin"),
        (Join-Path $AndroidSdkRoot "platform-tools"),
        (Join-Path $AndroidSdkRoot "build-tools\$($profile.build_tools)")
    )
    $pathValue = Add-PathEntry -Entries $pathEntries -ExistingPath $env:Path

    $envMap = [ordered]@{
        VITYO_ANDROID_PROFILE = $profile.name
        ANDROID_SDK_ROOT = $AndroidSdkRoot
        ANDROID_HOME = $AndroidSdkRoot
        VITYO_ANDROID_PLATFORM = $profile.platform
        VITYO_ANDROID_COMPILE_SDK = [string]$profile.compile_sdk
        VITYO_ANDROID_TARGET_SDK = [string]$profile.target_sdk
        VITYO_ANDROID_MIN_SDK = [string]$profile.min_sdk
        VITYO_ANDROID_BUILD_TOOLS = $profile.build_tools
        VITYO_ANDROID_NDK_VERSION = $profile.ndk_version
        ORG_GRADLE_PROJECT_vityoAndroidCompileSdk = [string]$profile.compile_sdk
        ORG_GRADLE_PROJECT_vityoAndroidTargetSdk = [string]$profile.target_sdk
        ORG_GRADLE_PROJECT_vityoAndroidMinSdk = [string]$profile.min_sdk
        ORG_GRADLE_PROJECT_vityoAndroidBuildToolsVersion = $profile.build_tools
        ORG_GRADLE_PROJECT_vityoAndroidNdkVersion = $profile.ndk_version
        ORG_GRADLE_PROJECT_vityoAndroidBuildRoot = "../../build/$($profile.name)"
        Path = $pathValue
    }
    if ($javaHome) {
        $envMap["JAVA_HOME"] = $javaHome
    }
    return $envMap
}

function Show-ProfileEnv {
    param([string]$ProfileName)
    if (-not $ProfileName) {
        $ProfileName = Get-DefaultProfileName
    }
    $envMap = Get-ProfileEnv -ProfileName $ProfileName
    foreach ($key in $envMap.Keys) {
        Write-Host "`$env:$key = `"$($envMap[$key])`""
    }
}

function Install-Profiles {
    param([string[]]$Args)
    $profilesCsv = "all"
    for ($i = 0; $i -lt $Args.Count; $i++) {
        switch ($Args[$i]) {
            "--profiles" { $profilesCsv = $Args[$i + 1]; $i++ }
            "--sdk-root" { $script:AndroidSdkRoot = $Args[$i + 1]; $i++ }
            default { }
        }
    }

    $sdkManager = Ensure-SdkManager
    $profileNames = Split-ProfileNames -Csv $profilesCsv

    Write-Log "accepting Android SDK licenses"
    & cmd /c "echo y| `"$sdkManager`" --sdk_root=`"$AndroidSdkRoot`" --licenses" | Out-Null

    Write-Log "installing shared Android SDK packages"
    & $sdkManager --sdk_root=$AndroidSdkRoot "platform-tools" | Out-Null

    foreach ($name in $profileNames) {
        $profile = Get-Profile $name
        Write-Log "installing Android SDK profile $name"
        & $sdkManager --sdk_root=$AndroidSdkRoot `
            "platforms;$($profile.platform)" `
            "build-tools;$($profile.build_tools)" `
            "ndk;$($profile.ndk_version)" | Out-Null
    }
}

function Invoke-ProfileRun {
    param([string[]]$Args)
    if ($Args.Count -eq 0) {
        Fail "run requires a profile and a command"
    }

    $profileName = $Args[0]
    $commandArgs = @()
    if ($Args.Count -gt 1) {
        $commandArgs = $Args[1..($Args.Count - 1)]
    }
    if ($commandArgs.Count -gt 0 -and $commandArgs[0] -eq "--") {
        $commandArgs = $commandArgs[1..($commandArgs.Count - 1)]
    }
    if ($commandArgs.Count -eq 0) {
        Fail "run requires a command after --"
    }

    $envMap = Get-ProfileEnv -ProfileName $profileName
    foreach ($key in $envMap.Keys) {
        Set-Item -Path "Env:$key" -Value $envMap[$key]
    }

    if ($commandArgs.Count -gt 1) {
        & $commandArgs[0] @($commandArgs[1..($commandArgs.Count - 1)])
    } else {
        & $commandArgs[0]
    }
}

function Copy-FlutterProject {
    param(
        [string]$SourceDir,
        [string]$DestinationRoot
    )

    $projectName = Split-Path $SourceDir -Leaf
    $destDir = Join-Path $DestinationRoot $projectName
    if (Test-Path $DestinationRoot) {
        Remove-Item -Recurse -Force $DestinationRoot
    }
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    $robocopyArgs = @(
        $SourceDir,
        $destDir,
        "/E",
        "/XD", "build", ".dart_tool", ".gradle", "ios\Pods", "ios\.symlinks", "macos\Pods", "macos\.symlinks",
        "/NFL", "/NDL", "/NJH", "/NJS", "/NP"
    )
    & robocopy @robocopyArgs | Out-Null
    if ($LASTEXITCODE -ge 8) {
        Fail "robocopy failed while preparing isolated Flutter workspace"
    }
    return $destDir
}

function Build-Profiles {
    param([string[]]$Args)
    Ensure-Flutter

    $profilesCsv = Get-DefaultProfileName
    $artifact = "apk"
    $mode = "debug"
    $parallel = $false
    $flutterDir = $FlutterDirDefault
    $outDir = $OutDirDefault
    $workDir = $WorkDirDefault
    $targetPlatform = $null
    $extraArgs = @()

    for ($i = 0; $i -lt $Args.Count; $i++) {
        switch ($Args[$i]) {
            "--profiles" { $profilesCsv = $Args[$i + 1]; $i++ }
            "--artifact" { $artifact = $Args[$i + 1]; $i++ }
            "--mode" { $mode = $Args[$i + 1]; $i++ }
            "--parallel" { $parallel = $true }
            "--flutter-dir" { $flutterDir = $Args[$i + 1]; $i++ }
            "--out-dir" { $outDir = $Args[$i + 1]; $i++ }
            "--work-dir" { $workDir = $Args[$i + 1]; $i++ }
            "--target-platform" { $targetPlatform = $Args[$i + 1]; $i++ }
            "--" {
                if ($i + 1 -lt $Args.Count) {
                    $extraArgs = $Args[($i + 1)..($Args.Count - 1)]
                }
                break
            }
            default { }
        }
    }

    $profileNames = Split-ProfileNames -Csv $profilesCsv
    New-Item -ItemType Directory -Path $outDir, $workDir -Force | Out-Null

    $buildOne = {
        param($ProfileName, $FlutterBin, $FlutterDir, $OutDir, $WorkDir, $Artifact, $Mode, $TargetPlatform, $ExtraArgs, $AndroidSdkRoot, $ProfileFile)

        $profileRows = Import-Csv -Path $ProfileFile
        $profile = $profileRows | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1
        if (-not $profile) {
            throw "Unknown Android profile: $ProfileName"
        }

        $workspaceRoot = Join-Path $WorkDir $ProfileName
        $appDir = Copy-FlutterProject -SourceDir $FlutterDir -DestinationRoot $workspaceRoot
        $outputsRoot = Join-Path $OutDir $ProfileName
        New-Item -ItemType Directory -Path $outputsRoot -Force | Out-Null

        $env:ANDROID_SDK_ROOT = $AndroidSdkRoot
        $env:ANDROID_HOME = $AndroidSdkRoot
        $env:VITYO_ANDROID_PROFILE = $profile.name
        $env:VITYO_ANDROID_PLATFORM = $profile.platform
        $env:VITYO_ANDROID_COMPILE_SDK = [string]$profile.compile_sdk
        $env:VITYO_ANDROID_TARGET_SDK = [string]$profile.target_sdk
        $env:VITYO_ANDROID_MIN_SDK = [string]$profile.min_sdk
        $env:VITYO_ANDROID_BUILD_TOOLS = $profile.build_tools
        $env:VITYO_ANDROID_NDK_VERSION = $profile.ndk_version
        $env:ORG_GRADLE_PROJECT_vityoAndroidCompileSdk = [string]$profile.compile_sdk
        $env:ORG_GRADLE_PROJECT_vityoAndroidTargetSdk = [string]$profile.target_sdk
        $env:ORG_GRADLE_PROJECT_vityoAndroidMinSdk = [string]$profile.min_sdk
        $env:ORG_GRADLE_PROJECT_vityoAndroidBuildToolsVersion = $profile.build_tools
        $env:ORG_GRADLE_PROJECT_vityoAndroidNdkVersion = $profile.ndk_version
        $env:ORG_GRADLE_PROJECT_vityoAndroidBuildRoot = "../../build/$($profile.name)"
        $env:Path = Add-PathEntry -Entries @(
            (Join-Path $AndroidSdkRoot "cmdline-tools\latest\bin"),
            (Join-Path $AndroidSdkRoot "platform-tools"),
            (Join-Path $AndroidSdkRoot "build-tools\$($profile.build_tools)")
        ) -ExistingPath $env:Path

        $cmd = @($FlutterBin, "build", $Artifact, "--$Mode", "--android-project-cache-dir", ".gradle-$ProfileName")
        $cmd += @("--android-project-arg", "vityoAndroidProfile=$ProfileName")
        $cmd += @("--android-project-arg", "vityoAndroidCompileSdk=$($profile.compile_sdk)")
        $cmd += @("--android-project-arg", "vityoAndroidTargetSdk=$($profile.target_sdk)")
        $cmd += @("--android-project-arg", "vityoAndroidMinSdk=$($profile.min_sdk)")
        $cmd += @("--android-project-arg", "vityoAndroidBuildToolsVersion=$($profile.build_tools)")
        $cmd += @("--android-project-arg", "vityoAndroidNdkVersion=$($profile.ndk_version)")
        $cmd += @("--android-project-arg", "vityoAndroidBuildRoot=../../build/$ProfileName")
        if ($TargetPlatform) {
            $cmd += @("--target-platform", $TargetPlatform)
        }
        if ($ExtraArgs) {
            $cmd += $ExtraArgs
        }

        Push-Location $appDir
        & $cmd[0] @($cmd[1..($cmd.Count - 1)])
        Pop-Location
    }

    if (-not $parallel -or $profileNames.Count -le 1) {
        foreach ($name in $profileNames) {
            & $buildOne $name $FlutterBin $flutterDir $outDir $workDir $artifact $mode $targetPlatform $extraArgs $AndroidSdkRoot $ProfileFile
        }
        return
    }

    $processes = @()
    foreach ($name in $profileNames) {
        $profileOutDir = Join-Path $outDir $name
        New-Item -ItemType Directory -Path $profileOutDir -Force | Out-Null
        $stdoutLog = Join-Path $profileOutDir "build.stdout.log"
        $stderrLog = Join-Path $profileOutDir "build.stderr.log"

        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $MyInvocation.MyCommand.Path,
            "build",
            "--profiles", $name,
            "--artifact", $artifact,
            "--mode", $mode,
            "--flutter-dir", $flutterDir,
            "--out-dir", $outDir,
            "--work-dir", $workDir
        )
        if ($targetPlatform) {
            $argList += @("--target-platform", $targetPlatform)
        }
        if ($extraArgs.Count -gt 0) {
            $argList += "--"
            $argList += $extraArgs
        }

        $process = Start-Process -FilePath "powershell" -ArgumentList $argList -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
        $processes += [pscustomobject]@{
            Name = $name
            Process = $process
            StdoutLog = $stdoutLog
            StderrLog = $stderrLog
        }
    }

    $failed = @()
    foreach ($entry in $processes) {
        Wait-Process -Id $entry.Process.Id
        if ($entry.Process.ExitCode -ne 0) {
            Write-Host "[android-sdk-profile] parallel build failed for $($entry.Name); see $($entry.StdoutLog) and $($entry.StderrLog)" -ForegroundColor Red
            $failed += $entry
        } else {
            Write-Host "[android-sdk-profile] parallel build completed for $($entry.Name); logs: $($entry.StdoutLog), $($entry.StderrLog)"
        }
    }
    if ($failed.Count -gt 0) {
        Fail "One or more parallel Android profile builds failed."
    }
}

switch ($Command) {
    "list" {
        "{0,-12} {1,-12} {2,-12} {3,-10} {4,-8} {5,-12} {6}" -f "profile", "platform", "compileSdk", "targetSdk", "minSdk", "buildTools", "default" | Write-Host
        foreach ($profile in Get-Profiles) {
            "{0,-12} {1,-12} {2,-12} {3,-10} {4,-8} {5,-12} {6}" -f $profile.name, $profile.platform, $profile.compile_sdk, $profile.target_sdk, $profile.min_sdk, $profile.build_tools, $profile.default_profile | Write-Host
        }
    }
    "install" {
        Install-Profiles -Args $RemainingArgs
    }
    "env" {
        $profileName = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { Get-DefaultProfileName }
        Show-ProfileEnv -ProfileName $profileName
    }
    "run" {
        Invoke-ProfileRun -Args $RemainingArgs
    }
    "build" {
        Build-Profiles -Args $RemainingArgs
    }
    "help" { Show-Usage }
    default { Show-Usage }
}
