[CmdletBinding()]
param(
    [ValidateSet('x64')]
    [string] $Target = 'x64',
    [ValidateSet('Debug', 'RelWithDebInfo', 'Release', 'MinSizeRel')]
    [string] $Configuration = 'Release',
    [string] $AwsSdkTag = '1.11.710'
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Resolve-Path -Path "$PSScriptRoot/../.."
$SourceDir = Join-Path $ProjectRoot 'aws-sdk-src'
$BuildDir = Join-Path $ProjectRoot 'aws-sdk-build-curl'
$InstallDir = Join-Path $ProjectRoot 'aws-sdk-built-curl'

$ObsDepsRoot = Join-Path $ProjectRoot '.deps'
if ( -not ( Test-Path $ObsDepsRoot ) ) {
    throw "Missing ${ObsDepsRoot}. Run .github/scripts/Build-Windows.ps1 once first so the pre-built obs-deps are downloaded, then re-run with -BuildAwsSdk."
}

$CurlHeader = Get-ChildItem -Path $ObsDepsRoot -Recurse -File -Filter 'curl.h' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\include\\curl\\curl\.h$' } |
    Sort-Object -Property FullName -Descending |
    Select-Object -First 1

if ( -not $CurlHeader ) {
    throw "Could not find curl headers under ${ObsDepsRoot} (expected include\\curl\\curl.h). Run .github/scripts/Build-Windows.ps1 once first so dependencies are downloaded."
}

$CurlIncludeDir = Split-Path -Parent (Split-Path -Parent $CurlHeader.FullName) # ...\include

$CurlLibCandidateNames = @(
    'libcurl_imp.lib',
    'libcurl.lib',
    'curl.lib'
)

$CurlLib = $null
foreach ( $CandidateName in $CurlLibCandidateNames ) {
    $Found = Get-ChildItem -Path $ObsDepsRoot -Recurse -File -Filter $CandidateName -ErrorAction SilentlyContinue |
        Sort-Object -Property FullName -Descending |
        Select-Object -First 1
    if ( $Found ) {
        $CurlLib = $Found.FullName
        break
    }
}

if ( -not $CurlLib ) {
    throw "Could not find a cURL import library under ${ObsDepsRoot} (tried: $($CurlLibCandidateNames -join ', ')). Ensure obs-deps are downloaded and include cURL."
}

if ( -not ( Test-Path $SourceDir ) ) {
    Write-Host "Cloning aws-sdk-cpp ${AwsSdkTag}..."
    git clone --depth 1 --branch $AwsSdkTag --recurse-submodules --shallow-submodules https://github.com/aws/aws-sdk-cpp.git $SourceDir
} else {
    Write-Host "Updating aws-sdk-cpp source in ${SourceDir}..."
    git -C $SourceDir fetch --tags --force
    git -C $SourceDir checkout $AwsSdkTag
}

Write-Host "Initializing aws-sdk-cpp submodules..."
git -C $SourceDir submodule sync --recursive
git -C $SourceDir submodule update --init --recursive

Write-Host "Configuring AWS SDK (TranscribeStreaming only)..."
cmake -S $SourceDir -B $BuildDir -G 'Visual Studio 17 2022' -A $Target `
    -DCMAKE_INSTALL_PREFIX="$InstallDir" `
    -DBUILD_ONLY=transcribestreaming `
    -DBUILD_SHARED_LIBS=OFF `
    -DENABLE_TESTING=OFF `
    -DLEGACY_BUILD=ON `
    -DAWS_SDK_WARNINGS_ARE_ERRORS=OFF `
    -DHTTP_CLIENT=CURL `
    -DUSE_CRT_HTTP_CLIENT=ON `
    -DENABLE_CURL_LOGGING=ON `
    -DCURL_INCLUDE_DIR="$CurlIncludeDir" `
    -DCURL_LIBRARY="$CurlLib"

Write-Host "Building + installing AWS SDK (${Configuration})..."
cmake --build $BuildDir --config $Configuration --target INSTALL --parallel

$SdkConfig = Join-Path $InstallDir 'lib/cmake/AWSSDK/AWSSDKConfig.cmake'
if ( -not ( Test-Path $SdkConfig ) ) {
    throw "AWS SDK install did not produce ${SdkConfig}"
}

Write-Host "AWS SDK installed to ${InstallDir}"
