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

$ObsDepsDir = Get-ChildItem -Path $ObsDepsRoot -Directory -Filter 'obs-deps-*-x64' |
    Sort-Object -Property Name -Descending |
    Select-Object -First 1

if ( -not $ObsDepsDir ) {
    throw "Could not find an obs-deps folder under ${ObsDepsRoot} (expected something like obs-deps-YYYY-MM-DD-x64)."
}

$CurlIncludeDir = Join-Path $ObsDepsDir.FullName 'include'
$CurlLib = Join-Path $ObsDepsDir.FullName 'lib/libcurl_imp.lib'

if ( -not ( Test-Path $CurlIncludeDir ) ) {
    throw "Missing curl include directory: ${CurlIncludeDir}"
}
if ( -not ( Test-Path $CurlLib ) ) {
    throw "Missing curl import library: ${CurlLib}"
}

if ( -not ( Test-Path $SourceDir ) ) {
    Write-Host "Cloning aws-sdk-cpp ${AwsSdkTag}..."
    git clone --depth 1 --branch $AwsSdkTag https://github.com/aws/aws-sdk-cpp.git $SourceDir
} else {
    Write-Host "Updating aws-sdk-cpp source in ${SourceDir}..."
    git -C $SourceDir fetch --tags --force
    git -C $SourceDir checkout $AwsSdkTag
}

Write-Host "Configuring AWS SDK (TranscribeStreaming only)..."
cmake -S $SourceDir -B $BuildDir -G 'Visual Studio 17 2022' -A $Target `
    -DCMAKE_INSTALL_PREFIX="$InstallDir" `
    -DBUILD_ONLY=transcribestreaming `
    -DBUILD_SHARED_LIBS=OFF `
    -DENABLE_TESTING=OFF `
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
