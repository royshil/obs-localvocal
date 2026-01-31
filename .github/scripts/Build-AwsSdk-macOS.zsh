#!/usr/bin/env zsh

builtin emulate -L zsh
setopt ERR_EXIT
setopt ERR_RETURN
setopt NO_UNSET
setopt PIPE_FAIL

usage() {
  print -u2 "Usage: ${0:t} [-c <config>] [-t <aws-sdk-tag>] [-a <arch>]"
  print -u2 "  -c   CMake build type (Release|RelWithDebInfo|Debug|MinSizeRel). Default: RelWithDebInfo"
  print -u2 "  -t   aws-sdk-cpp git tag. Default: 1.11.710"
  print -u2 "  -a   macOS arch (arm64|x86_64). Default: \$MACOS_ARCH or host arch"
}

config="${AWS_SDK_CONFIG:-RelWithDebInfo}"
tag="${AWS_SDK_TAG:-1.11.710}"
arch="${MACOS_ARCH:-}"

while getopts ":c:t:a:h" opt; do
  case "${opt}" in
    c) config="${OPTARG}" ;;
    t) tag="${OPTARG}" ;;
    a) arch="${OPTARG}" ;;
    h) usage; exit 0 ;;
    \?) usage; exit 2 ;;
  esac
done

if [[ -z "${arch}" ]]; then
  arch="$(uname -m)"
fi

script_dir="${0:A:h}"
project_root="${script_dir:A:h:h}"

source_dir="${project_root}/aws-sdk-src"
build_dir="${project_root}/aws-sdk-build-curl-macos-${arch}"
install_dir="${project_root}/aws-sdk-built-curl"
sdk_config="${install_dir}/lib/cmake/AWSSDK/AWSSDKConfig.cmake"

print -r -- "=> Building AWS SDK for TranscribeStreaming (macOS ${arch}, tag ${tag})"

if [[ ! -d "${source_dir}" ]]; then
  git clone --depth 1 --branch "${tag}" --recurse-submodules --shallow-submodules \
    https://github.com/aws/aws-sdk-cpp.git "${source_dir}"
else
  git -C "${source_dir}" fetch --tags --force
  git -C "${source_dir}" checkout "${tag}"
fi

git -C "${source_dir}" submodule sync --recursive
git -C "${source_dir}" submodule update --init --recursive

cmake_args=(
  -S "${source_dir}"
  -B "${build_dir}"
  -G "Ninja"
  -DCMAKE_INSTALL_PREFIX="${install_dir}"
  -DCMAKE_BUILD_TYPE="${config}"
  -DCMAKE_OSX_ARCHITECTURES="${arch}"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${AWS_SDK_MACOS_DEPLOYMENT_TARGET:-12.0}"
  -DBUILD_ONLY=transcribestreaming
  -DBUILD_SHARED_LIBS=OFF
  -DENABLE_TESTING=OFF
  -DLEGACY_BUILD=ON
  -DAWS_SDK_WARNINGS_ARE_ERRORS=OFF
  -DHTTP_CLIENT=CURL
  -DUSE_CRT_HTTP_CLIENT=ON
  -DENABLE_CURL_LOGGING=ON
  -DENABLE_OPENSSL_ENCRYPTION=OFF
  -DENABLE_COMMONCRYPTO_ENCRYPTION=ON
)

cmake "${cmake_args[@]}"
cmake --build "${build_dir}" --target install --parallel

if [[ ! -r "${sdk_config}" ]]; then
  print -u2 "ERROR: AWS SDK install did not produce ${sdk_config}"
  exit 1
fi

print -r -- "=> AWS SDK installed to ${install_dir}"
