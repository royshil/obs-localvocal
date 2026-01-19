[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string] $Target = 'x64',
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'RelWithDebInfo',
    [switch] $SkipAll,
    [switch] $SkipBuild,
    [switch] $SkipDeps,
    [switch] $BuildAwsSdk = $true,
    [string] $AwsSdkTag = '1.11.710',
    [string] $AwsSdkRoot,
    [string[]] $ExtraCmakeArgs
)

$ErrorActionPreference = 'Stop'

if ( $DebugPreference -eq 'Continue' ) {
    $VerbosePreference = 'Continue'
    $InformationPreference = 'Continue'
}

if ( ! ( [System.Environment]::Is64BitOperatingSystem ) ) {
    throw "A 64-bit system is required to build the project."
}

if ( $PSVersionTable.PSVersion -lt '7.0.0' ) {
    Write-Warning 'The obs-deps PowerShell build script requires PowerShell Core 7. Install or upgrade your PowerShell version: https://aka.ms/pscore6'
    exit 2
}

function Build {
    trap {
        Pop-Location -Stack BuildTemp -ErrorAction 'SilentlyContinue'
        Write-Error $_
        Log-Group
        exit 2
    }

    $ScriptHome = $PSScriptRoot
    $ProjectRoot = Resolve-Path -Path "$PSScriptRoot/../.."
    $BuildSpecFile = "${ProjectRoot}/buildspec.json"

    $UtilityFunctions = Get-ChildItem -Path $PSScriptRoot/utils.pwsh/*.ps1 -Recurse

    foreach($Utility in $UtilityFunctions) {
        Write-Debug "Loading $($Utility.FullName)"
        . $Utility.FullName
    }

    $BuildSpec = Get-Content -Path ${BuildSpecFile} -Raw | ConvertFrom-Json
    $ProductName = $BuildSpec.name
    $ProductVersion = $BuildSpec.version

    if ( ! $SkipDeps ) {
        Install-BuildDependencies -WingetFile "${ScriptHome}/.Wingetfile"
    }

    Push-Location -Stack BuildTemp
    if ( ! ( ( $SkipAll ) -or ( $SkipBuild ) ) ) {
        Ensure-Location $ProjectRoot

        # take cmake args from $ExtraCmakeArgs
        $CmakeArgs = $ExtraCmakeArgs
        $CmakeBuildArgs = @()
        $CmakeInstallArgs = @()

        # If AWS Transcribe is explicitly disabled via CMake, don't attempt to build the AWS SDK.
        # Users can still force an SDK build with -BuildAwsSdk:$true.
        $AwsTranscribeDisabled = $false
        foreach ( $Arg in $CmakeArgs ) {
            if ( $Arg -match '^-DENABLE_AWS_TRANSCRIBE(:BOOL)?=(0|OFF|FALSE)$' ) {
                $AwsTranscribeDisabled = $true
                break
            }
        }
        if ( $AwsTranscribeDisabled -and ( -not $PSBoundParameters.ContainsKey('BuildAwsSdk') ) ) {
            $BuildAwsSdk = $false
        }

        if ( $VerbosePreference -eq 'Continue' ) {
            $CmakeBuildArgs += ('--verbose')
            $CmakeInstallArgs += ('--verbose')
        }

        if ( $DebugPreference -eq 'Continue' ) {
            $CmakeArgs += ('--debug-output')
        }

        $Preset = "windows-$(if ( $Env:CI -ne $null ) { 'ci-' })${Target}"

        $CmakeArgs += @(
            '--preset', $Preset
        )

        $CmakeBuildArgs += @(
            '--build'
            '--preset', $Preset
            '--config', $Configuration
            '--parallel'
            '--', '/consoleLoggerParameters:Summary', '/noLogo'
        )

        $CmakeInstallArgs += @(
            '--install', "build_${Target}"
            '--prefix', "${ProjectRoot}/release/${Configuration}"
            '--config', $Configuration
        )

        $RepoLocalAwsSdkRoot = "${ProjectRoot}/aws-sdk-built-curl"
        $RepoLocalAwsSdkConfig = "${RepoLocalAwsSdkRoot}/lib/cmake/AWSSDK/AWSSDKConfig.cmake"

        if ( $BuildAwsSdk -and ( -not $AwsSdkRoot ) -and ( Test-Path $RepoLocalAwsSdkConfig ) ) {
            $AwsSdkRoot = $RepoLocalAwsSdkRoot
        }

        $NeedAwsSdkBuild = $BuildAwsSdk -and ( -not $AwsSdkRoot ) -and ( -not ( Test-Path $RepoLocalAwsSdkConfig ) )
        if ( $NeedAwsSdkBuild ) {
            Log-Group "Configuring ${ProductName} (bootstrap deps for AWS SDK)..."
            Invoke-External cmake @CmakeArgs

            Log-Group "Building AWS SDK for Transcribe (tag ${AwsSdkTag})..."
            try {
                $PwshArgs = @(
                    '-NoProfile'
                    '-ExecutionPolicy', 'Bypass'
                    '-File', "${ScriptHome}/Build-AwsSdk-Windows.ps1"
                    '-Target', $Target
                    '-Configuration', $Configuration
                    '-AwsSdkTag', $AwsSdkTag
                )
                Invoke-External pwsh @PwshArgs
            } catch {
                Write-Warning "AWS SDK build failed; continuing without AWS Transcribe streaming support. To skip the SDK build attempt, pass -BuildAwsSdk:`$false or -ExtraCmakeArgs '-DENABLE_AWS_TRANSCRIBE=OFF'."
                $BuildAwsSdk = $false
            }

            if ( Test-Path $RepoLocalAwsSdkConfig ) {
                $AwsSdkRoot = $RepoLocalAwsSdkRoot
            }
        }

        if ( $AwsSdkRoot ) {
            $CmakeArgs += @(
                "-DAWS_SDK_ROOT=${AwsSdkRoot}"
            )
        }

        Log-Group "Configuring ${ProductName}..."
        Invoke-External cmake @CmakeArgs

        if ( Test-Path "build_${Target}/CMakeCache.txt" ) {
            $TranscribeSdkNotFound = Select-String -Path "build_${Target}/CMakeCache.txt" -Pattern '^aws-cpp-sdk-transcribestreaming_DIR:PATH=.*NOTFOUND$' -Quiet
            if ( $TranscribeSdkNotFound ) {
                Write-Warning "AWS SDK TranscribeStreaming not found; AWS Transcribe streaming support will be disabled. Provide -AwsSdkRoot=... or re-run with -BuildAwsSdk."
            }
        }

        Log-Group "Building ${ProductName}..."
        Invoke-External cmake @CmakeBuildArgs
    }
    Log-Group "Install ${ProductName}..."
    Invoke-External cmake @CmakeInstallArgs

    Pop-Location -Stack BuildTemp
    Log-Group
}

Build
