include(ExternalProject)
include(FetchContent)

set(PREBUILT_WHISPERCPP_VERSION "0.0.8-1")
set(PREBUILT_WHISPERCPP_URL_BASE
  "https://github.com/locaal-ai/occ-ai-dep-whispercpp/releases/download/${PREBUILT_WHISPERCPP_VERSION}")

if(APPLE)
  # check the "MACOS_ARCH" env var to figure out if this is x86 or arm64
  if($ENV{MACOS_ARCH} STREQUAL "x86_64")
    set(WHISPER_CPP_HASH "3c3d070103903418100c7bc7251d9a291a42e365ab123cdfd4a0bedc2474ad5a")
  elseif($ENV{MACOS_ARCH} STREQUAL "arm64")
    set(WHISPER_CPP_HASH "5e844f5941a6fcdad14087dcb011de450a0ffebce1bbbfa5215c61d7f1168a02")
  else()
    message(
      FATAL_ERROR
      "The MACOS_ARCH environment variable is not set to a valid value. Please set it to either `x86_64` or `arm64`")
  endif()

  set(WHISPER_CPP_URL
    "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-macos-$ENV{MACOS_ARCH}-${PREBUILT_WHISPERCPP_VERSION}.tar.gz")

  FetchContent_Declare(
    whispercpp_fetch
    URL ${WHISPER_CPP_URL}
    URL_HASH SHA256=${WHISPER_CPP_HASH})
  FetchContent_MakeAvailable(whispercpp_fetch)

  add_library(Whispercpp::Whisper STATIC IMPORTED)
  set_target_properties(
    Whispercpp::Whisper
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}whisper${CMAKE_STATIC_LIBRARY_SUFFIX})
  set_target_properties(Whispercpp::Whisper PROPERTIES INTERFACE_INCLUDE_DIRECTORIES
    ${whispercpp_fetch_SOURCE_DIR}/include)
  add_library(Whispercpp::GGML STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGML
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml${CMAKE_STATIC_LIBRARY_SUFFIX})
  add_library(Whispercpp::GGMLBase STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGMLBase
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-base${CMAKE_STATIC_LIBRARY_SUFFIX})
  add_library(Whispercpp::GGMLCPU STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGMLCPU
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-cpu${CMAKE_STATIC_LIBRARY_SUFFIX})
  add_library(Whispercpp::GGMLMetal STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGMLMetal
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-metal${CMAKE_STATIC_LIBRARY_SUFFIX}
  )
  add_library(Whispercpp::GGMLBlas STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGMLBlas
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-blas${CMAKE_STATIC_LIBRARY_SUFFIX})

elseif(WIN32)
  if(NOT DEFINED ACCELERATION)
    message(FATAL_ERROR "ACCELERATION is not set. Please set it to either `cpu`, `cuda`, `vulkan` or `hipblas`")
  endif()

  set(ARCH_PREFIX ${ACCELERATION})
  set(WHISPER_CPP_URL
    "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-windows-${ARCH_PREFIX}-${PREBUILT_WHISPERCPP_VERSION}.zip")

  if("${ACCELERATION}" STREQUAL "cpu")
    set(WHISPER_CPP_HASH "f701d966efad4edfba95d493f71973f9025508dd652c00d0386c5e8bb8d43f80")
    add_compile_definitions("LOCALVOCAL_WITH_CPU")
  elseif("${ACCELERATION}" STREQUAL "cuda")
    set(WHISPER_CPP_HASH "a024230dc521146072aff56433cd3300d988be0c7c31a1128382918a94e5e0dd")
    add_compile_definitions("LOCALVOCAL_WITH_CUDA")
  elseif("${ACCELERATION}" STREQUAL "hipblas")
    set(WHISPER_CPP_HASH "037d441e130ca881c209b57db1e901f1e09f56968c4310065ba385eba77fc4ea")
    add_compile_definitions("LOCALVOCAL_WITH_HIPBLAS")
  elseif("${ACCELERATION}" STREQUAL "vulkan")
    set(WHISPER_CPP_HASH "2723fb5f44bc4798c5d1f724bd0bcdd7417ab8136f6b460c6c2f05205f712dd4")
    add_compile_definitions("LOCALVOCAL_WITH_VULKAN")
  else()
    message(
      FATAL_ERROR
      "The ACCELERATION environment variable is not set to a valid value. Please set it to either `cpu` or `cuda` or `vulkan` or `hipblas`"
    )
  endif()

  FetchContent_Declare(
    whispercpp_fetch
    URL ${WHISPER_CPP_URL}
    URL_HASH SHA256=${WHISPER_CPP_HASH}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  FetchContent_MakeAvailable(whispercpp_fetch)

  add_library(Whispercpp::Whisper SHARED IMPORTED)
  set_target_properties(
    Whispercpp::Whisper
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/bin/${CMAKE_SHARED_LIBRARY_PREFIX}whisper${CMAKE_SHARED_LIBRARY_SUFFIX})
  set_target_properties(
    Whispercpp::Whisper
    PROPERTIES IMPORTED_IMPLIB
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}whisper${CMAKE_STATIC_LIBRARY_SUFFIX})

  add_library(Whispercpp::GGML SHARED IMPORTED)
  set_target_properties(
    Whispercpp::GGML
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/bin/${CMAKE_SHARED_LIBRARY_PREFIX}ggml${CMAKE_SHARED_LIBRARY_SUFFIX})
  set_target_properties(
    Whispercpp::GGML
    PROPERTIES IMPORTED_IMPLIB
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml${CMAKE_STATIC_LIBRARY_SUFFIX})

  add_library(Whispercpp::GGMLBase SHARED IMPORTED)
  set_target_properties(
    Whispercpp::GGMLBase
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/bin/${CMAKE_SHARED_LIBRARY_PREFIX}ggml-base${CMAKE_SHARED_LIBRARY_SUFFIX})
  set_target_properties(
    Whispercpp::GGMLBase
    PROPERTIES IMPORTED_IMPLIB
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-base${CMAKE_STATIC_LIBRARY_SUFFIX})

  add_library(Whispercpp::GGMLCPU SHARED IMPORTED)
  set_target_properties(
    Whispercpp::GGMLCPU
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/bin/${CMAKE_SHARED_LIBRARY_PREFIX}ggml-cpu${CMAKE_SHARED_LIBRARY_SUFFIX})
  set_target_properties(
    Whispercpp::GGMLCPU
    PROPERTIES IMPORTED_IMPLIB
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-cpu${CMAKE_STATIC_LIBRARY_SUFFIX})

  set_target_properties(Whispercpp::Whisper PROPERTIES INTERFACE_INCLUDE_DIRECTORIES
    ${whispercpp_fetch_SOURCE_DIR}/include)

  if("${ACCELERATION}" STREQUAL "cpu")
    # add openblas to the link line
    add_library(Whispercpp::OpenBLAS STATIC IMPORTED)
    set_target_properties(Whispercpp::OpenBLAS PROPERTIES IMPORTED_LOCATION
      ${whispercpp_fetch_SOURCE_DIR}/lib/libopenblas.dll.a)
  endif()

  if("${ACCELERATION}" STREQUAL "cuda")
    # add cuda to the link line
    add_library(Whispercpp::GGMLCUDA SHARED IMPORTED)
    set_target_properties(
      Whispercpp::GGMLCUDA
      PROPERTIES
      IMPORTED_LOCATION
      ${whispercpp_fetch_SOURCE_DIR}/bin/${CMAKE_SHARED_LIBRARY_PREFIX}ggml-cuda${CMAKE_SHARED_LIBRARY_SUFFIX})
    set_target_properties(
      Whispercpp::GGMLCUDA
      PROPERTIES
      IMPORTED_IMPLIB
      ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-cuda${CMAKE_STATIC_LIBRARY_SUFFIX})
  endif()

  if("${ACCELERATION}" STREQUAL "vulkan")
    # add cuda to the link line
    add_library(Whispercpp::GGMLVulkan SHARED IMPORTED)
    set_target_properties(
      Whispercpp::GGMLVulkan
      PROPERTIES
      IMPORTED_LOCATION
      ${whispercpp_fetch_SOURCE_DIR}/bin/${CMAKE_SHARED_LIBRARY_PREFIX}ggml-vulkan${CMAKE_SHARED_LIBRARY_SUFFIX})
    set_target_properties(
      Whispercpp::GGMLVulkan
      PROPERTIES
      IMPORTED_IMPLIB
      ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-vulkan${CMAKE_STATIC_LIBRARY_SUFFIX})
  endif()

  # glob all dlls in the bin directory and install them
  file(GLOB WHISPER_DLLS ${whispercpp_fetch_SOURCE_DIR}/bin/*.dll)
  install(FILES ${WHISPER_DLLS} DESTINATION "obs-plugins/64bit")
else()
  if(NOT DEFINED ACCELERATION)
    message(FATAL_ERROR "ACCELERATION is not set. Please set it to either `cpu`, or `vulkan`")
  endif()

  set(WHISPER_CPP_URL "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-linux-x86_64-${ACCELERATION}-Release.tar.gz")

  if("${ACCELERATION}" STREQUAL "cpu")
    set(WHISPER_CPP_HASH "e4a46b1266899f52cd35c7a3f36eb4f0e32f311152b55ea01aacf20a52d6c036")
    add_compile_definitions("LOCALVOCAL_WITH_CPU")
  elseif("${ACCELERATION}" STREQUAL "vulkan")
    set(WHISPER_CPP_HASH "e05be392d79bd184baf042781523f4f22823db2edaa8c75bc2b53aa2cc4904ab")
    add_compile_definitions("LOCALVOCAL_WITH_VULKAN")
  else()
    message(
      FATAL_ERROR
      "The ACCELERATION environment variable is not set to a valid value. Please set it to either `cpu` or `vulkan`")
  endif()

  FetchContent_Declare(
    whispercpp_fetch
    URL ${WHISPER_CPP_URL}
    URL_HASH SHA256=${WHISPER_CPP_HASH}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  FetchContent_MakeAvailable(whispercpp_fetch)

  message(STATUS "Whispercpp URL: ${WHISPER_CPP_URL}")
  message(STATUS "Whispercpp source dir: ${whispercpp_fetch_SOURCE_DIR}")

  # add the static Whisper library to the link line
  add_library(Whispercpp::Whisper STATIC IMPORTED)
  set_target_properties(
    Whispercpp::Whisper
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}whisper${CMAKE_STATIC_LIBRARY_SUFFIX})
  set_target_properties(Whispercpp::Whisper PROPERTIES INTERFACE_INCLUDE_DIRECTORIES
    ${whispercpp_fetch_SOURCE_DIR}/include)
  add_library(Whispercpp::GGML STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGML
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml${CMAKE_STATIC_LIBRARY_SUFFIX})
  add_library(Whispercpp::GGMLBase STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGMLBase
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-base${CMAKE_STATIC_LIBRARY_SUFFIX})
  add_library(Whispercpp::GGMLCPU STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGMLCPU
    PROPERTIES IMPORTED_LOCATION
    ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-cpu${CMAKE_STATIC_LIBRARY_SUFFIX})

  if("${ACCELERATION}" STREQUAL "vulkan")
    add_library(Whispercpp::GGMLVulkan STATIC IMPORTED)
    set_target_properties(
      Whispercpp::GGMLVulkan
      PROPERTIES
      IMPORTED_LOCATION
      ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-vulkan${CMAKE_STATIC_LIBRARY_SUFFIX})
  endif()
endif()

add_library(Whispercpp INTERFACE)
add_dependencies(Whispercpp Whispercpp_Build)
target_link_libraries(Whispercpp INTERFACE Whispercpp::Whisper Whispercpp::GGML Whispercpp::GGMLBase
  Whispercpp::GGMLCPU)

if(WIN32 AND "${ACCELERATION}" STREQUAL "cpu")
  target_link_libraries(Whispercpp INTERFACE Whispercpp::OpenBLAS)
endif()

if(WIN32 AND "${ACCELERATION}" STREQUAL "vulkan")
  target_link_libraries(Whispercpp INTERFACE Whispercpp::GGMLVulkan)
endif()

if(WIN32 AND "${ACCELERATION}" STREQUAL "cuda")
  target_link_libraries(Whispercpp INTERFACE Whispercpp::GGMLCUDA)
endif()

if(APPLE)
  target_link_libraries(Whispercpp INTERFACE "-framework Accelerate -framework CoreML -framework Metal")
  target_link_libraries(Whispercpp INTERFACE Whispercpp::GGMLMetal Whispercpp::GGMLBlas)
endif(APPLE)

if(UNIX
  AND(NOT APPLE)
  AND "${ACCELERATION}" STREQUAL "vulkan")
  target_link_libraries(Whispercpp INTERFACE Whispercpp::GGMLVulkan)
endif()
