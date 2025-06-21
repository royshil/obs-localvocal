include(ExternalProject)
include(FetchContent)

set(PREBUILT_WHISPERCPP_VERSION "0.0.7")
set(PREBUILT_WHISPERCPP_URL_BASE
    "https://github.com/locaal-ai/occ-ai-dep-whispercpp/releases/download/${PREBUILT_WHISPERCPP_VERSION}")

if(APPLE)
  # check the "MACOS_ARCH" env var to figure out if this is x86 or arm64
  if($ENV{MACOS_ARCH} STREQUAL "x86_64")
    set(WHISPER_CPP_HASH "dc7fd5ff9c7fbb8623f8e14d9ff2872186cab4cd7a52066fcb2fab790d6092fc")
  elseif($ENV{MACOS_ARCH} STREQUAL "arm64")
    set(WHISPER_CPP_HASH "ebed595ee431b182261bce41583993b149eed539e15ebf770d98a6bc85d53a92")
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

  add_library(Whispercpp::CoreML STATIC IMPORTED)
  set_target_properties(
    Whispercpp::CoreML
    PROPERTIES
      IMPORTED_LOCATION
      ${whispercpp_fetch_SOURCE_DIR}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}whisper.coreml${CMAKE_STATIC_LIBRARY_SUFFIX})

elseif(WIN32)
  if(NOT DEFINED ACCELERATION)
    message(FATAL_ERROR "ACCELERATION is not set. Please set it to either `cpu`, `cuda`, `vulkan` or `hipblas`")
  endif()

  set(ARCH_PREFIX ${ACCELERATION})
  set(WHISPER_CPP_URL
      "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-windows-${ARCH_PREFIX}-${PREBUILT_WHISPERCPP_VERSION}.zip")
  if(${ACCELERATION} STREQUAL "cpu")
    set(WHISPER_CPP_HASH "c23862b4aac7d8448cf7de4d339a86498f88ecba6fa7d243bbd7fabdb13d4dd4")
    add_compile_definitions("LOCALVOCAL_WITH_CPU")
  elseif(${ACCELERATION} STREQUAL "cuda")
    set(WHISPER_CPP_HASH "a0adeaccae76fab0678d016a62b79a19661ed34eb810d8bae3b610345ee9a405")
    add_compile_definitions("LOCALVOCAL_WITH_CUDA")
  elseif(${ACCELERATION} STREQUAL "hipblas")
    set(WHISPER_CPP_HASH "bbad0b4eec01c5a801d384c03745ef5e97061958f8cf8f7724281d433d7d92a1")
    add_compile_definitions("LOCALVOCAL_WITH_HIPBLAS")
  elseif(${ACCELERATION} STREQUAL "vulkan")
    set(WHISPER_CPP_HASH "12bb34821f9efcd31f04a487569abff2b669221f2706fe0d09c17883635ef58a")
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
  set_target_properties(Whispercpp::Whisper PROPERTIES INTERFACE_INCLUDE_DIRECTORIES
                                                       ${whispercpp_fetch_SOURCE_DIR}/include)

  if(${ACCELERATION} STREQUAL "cpu")
    # add openblas to the link line
    add_library(Whispercpp::OpenBLAS STATIC IMPORTED)
    set_target_properties(Whispercpp::OpenBLAS PROPERTIES IMPORTED_LOCATION
                                                          ${whispercpp_fetch_SOURCE_DIR}/lib/libopenblas.dll.a)
  endif()

  # glob all dlls in the bin directory and install them
  file(GLOB WHISPER_DLLS ${whispercpp_fetch_SOURCE_DIR}/bin/*.dll)
  install(FILES ${WHISPER_DLLS} DESTINATION "obs-plugins/64bit")
else()
  # Enable ccache if available
  find_program(CCACHE_PROGRAM ccache)
  if(CCACHE_PROGRAM)
    message(STATUS "Found ccache: ${CCACHE_PROGRAM}")
    set(CMAKE_C_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
    set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
  endif()

  if(${CMAKE_BUILD_TYPE} STREQUAL Release OR ${CMAKE_BUILD_TYPE} STREQUAL RelWithDebInfo)
    set(Whispercpp_BUILD_TYPE Release)
  else()
    set(Whispercpp_BUILD_TYPE Debug)
  endif()
  set(Whispercpp_Build_GIT_TAG "v1.7.5")
  set(WHISPER_EXTRA_CXX_FLAGS "-fPIC")
  set(WHISPER_LIBRARIES Whisper GGML GGMLBase GGMLCPU)
  set(WHISPER_IMPORT_LIBRARIES whisper ggml ggml-base ggml-cpu)

  # TODO: Add hipBLAS, OpenCL, and SYCL support

  set(ARCH_PREFIX ${ACCELERATION})
  if(${ACCELERATION} STREQUAL "cpu-blas")
    set(BLA_VENDOR "OpenBLAS")
    find_package(CBLAS)
    message(STATUS "CBLAS found, Libraries: ${CBLAS_LIBRARIES}")
    add_compile_definitions("LOCALVOCAL_WITH_CPU")
    set(WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_BLAS=ON)
    list(APPEND WHISPER_LIBRARIES GGMLBlas)
    list(APPEND WHISPER_IMPORT_LIBRARIES ggml-blas)
  elseif(${ACCELERATION} STREQUAL "cuda")
    find_package(CUDAToolkit REQUIRED)
    set(WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=native)
    add_compile_definitions("LOCALVOCAL_WITH_CUDA")
    list(APPEND WHISPER_LIBRARIES GGMLCUDA)
    list(APPEND WHISPER_IMPORT_LIBRARIES ggml-cuda)
  elseif(${ACCELERATION} STREQUAL "vulkan")
    find_package(
      Vulkan
      COMPONENTS glslc
      REQUIRED)
    set(WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_VULKAN=ON)
    add_compile_definitions("LOCALVOCAL_WITH_VULKAN")
    list(APPEND WHISPER_LIBRARIES GGMLVulkan)
    list(APPEND WHISPER_IMPORT_LIBRARIES ggml-vulkan)
  else()
    message(
      STATUS
        "The ACCELERATION environment variable is not set. Defaulting to `cpu`. Possible values: `cpu`, `cpu-blas`, `cuda` or `vulkan`"
    )
    add_compile_definitions("LOCALVOCAL_WITH_CPU")
  endif()

  foreach(importlib ${WHISPER_IMPORT_LIBRARIES})
    list(APPEND WHISPER_BYPRODUCTS <INSTALL_DIR>/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}${importlib}${CMAKE_STATIC_LIBRARY_SUFFIX})
  endforeach(importlib ${WHISPER_IMPORT_LIBRARIES})

  # On Linux build a static Whisper library
  ExternalProject_Add(
    Whispercpp_Build
    DOWNLOAD_EXTRACT_TIMESTAMP true
    GIT_REPOSITORY https://github.com/ggerganov/whisper.cpp.git
    GIT_TAG ${Whispercpp_Build_GIT_TAG}
    BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --config ${Whispercpp_BUILD_TYPE}
    BUILD_BYPRODUCTS ${WHISPER_BYPRODUCTS}
    CMAKE_GENERATOR ${CMAKE_GENERATOR}
    INSTALL_COMMAND ${CMAKE_COMMAND} --install <BINARY_DIR> --config ${Whispercpp_BUILD_TYPE} && ${CMAKE_COMMAND} -E
                    copy <SOURCE_DIR>/ggml/include/ggml.h <INSTALL_DIR>/include
    CONFIGURE_COMMAND
      ${CMAKE_COMMAND} -E env ${WHISPER_ADDITIONAL_ENV} ${CMAKE_COMMAND} <SOURCE_DIR> -B <BINARY_DIR> -G
      ${CMAKE_GENERATOR} -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR> -DCMAKE_INSTALL_LIBDIR=${CMAKE_INSTALL_LIBDIR}
      -DCMAKE_BUILD_TYPE=${Whispercpp_BUILD_TYPE} -DCMAKE_GENERATOR_PLATFORM=${CMAKE_GENERATOR_PLATFORM}
      -DCMAKE_CXX_FLAGS=${WHISPER_EXTRA_CXX_FLAGS} -DCMAKE_C_FLAGS=${WHISPER_EXTRA_CXX_FLAGS}
      -DCMAKE_CUDA_FLAGS=${WHISPER_EXTRA_CXX_FLAGS} -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF
      -DWHISPER_BUILD_EXAMPLES=OFF ${WHISPER_ADDITIONAL_CMAKE_ARGS})

  ExternalProject_Get_Property(Whispercpp_Build INSTALL_DIR)

  # add the static Whisper libraries to the link line
  add_library(Whispercpp::Whisper STATIC IMPORTED)
  set_target_properties(
    Whispercpp::Whisper
    PROPERTIES
      IMPORTED_LOCATION
      ${INSTALL_DIR}/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}whisper${CMAKE_STATIC_LIBRARY_SUFFIX})
  set_target_properties(Whispercpp::Whisper PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${INSTALL_DIR}/include)

  add_library(Whispercpp::GGML STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGML
    PROPERTIES IMPORTED_LOCATION
               ${INSTALL_DIR}/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}ggml${CMAKE_STATIC_LIBRARY_SUFFIX})
  set_target_properties(Whispercpp::GGML PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${INSTALL_DIR}/include)

  add_library(Whispercpp::GGMLBase STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGMLBase
    PROPERTIES
      IMPORTED_LOCATION
      ${INSTALL_DIR}/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-base${CMAKE_STATIC_LIBRARY_SUFFIX})
  set_target_properties(Whispercpp::GGMLBase PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${INSTALL_DIR}/include)

  add_library(Whispercpp::GGMLCPU STATIC IMPORTED)
  set_target_properties(
    Whispercpp::GGMLCPU
    PROPERTIES
      IMPORTED_LOCATION
      ${INSTALL_DIR}/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-cpu${CMAKE_STATIC_LIBRARY_SUFFIX})
  set_target_properties(Whispercpp::GGMLCPU PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${INSTALL_DIR}/include)

  if(${ACCELERATION} STREQUAL "cpu-blas")
    add_library(Whispercpp::GGMLBlas STATIC IMPORTED)
    set_target_properties(
      Whispercpp::GGMLBlas
      PROPERTIES
        IMPORTED_LOCATION
        ${INSTALL_DIR}/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-blas${CMAKE_STATIC_LIBRARY_SUFFIX})
    set_target_properties(Whispercpp::GGMLBlas PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${INSTALL_DIR}/include)
  elseif(${ACCELERATION} STREQUAL "cuda")
    add_library(Whispercpp::GGMLCUDA STATIC IMPORTED)
    set_target_properties(
      Whispercpp::GGMLCUDA
      PROPERTIES
        IMPORTED_LOCATION
        ${INSTALL_DIR}/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-cuda${CMAKE_STATIC_LIBRARY_SUFFIX})
    set_target_properties(Whispercpp::GGMLCUDA PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${INSTALL_DIR}/include)
  elseif(${ACCELERATION} STREQUAL "vulkan")
    add_library(Whispercpp::GGMLVulkan STATIC IMPORTED)
    set_target_properties(
      Whispercpp::GGMLVulkan
      PROPERTIES
        IMPORTED_LOCATION
        ${INSTALL_DIR}/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}ggml-vulkan${CMAKE_STATIC_LIBRARY_SUFFIX})
    set_target_properties(Whispercpp::GGMLVulkan PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${INSTALL_DIR}/include)
  endif()
endif()

add_library(Whispercpp INTERFACE)
add_dependencies(Whispercpp Whispercpp_Build)
if(WIN32)
  target_link_libraries(Whispercpp INTERFACE Whispercpp::Whisper)
  if("${ACCELERATION}" STREQUAL "cpu")
    target_link_libraries(Whispercpp INTERFACE Whispercpp::OpenBLAS)
  endif()
elseif(APPLE)
  target_link_libraries(Whispercpp INTERFACE "-framework Accelerate -framework CoreML -framework Metal")
  target_link_libraries(Whispercpp INTERFACE Whispercpp::Whisper Whispercpp::GGML Whispercpp::CoreML)
else()
  foreach(lib ${WHISPER_LIBRARIES})
    message(STATUS "Adding " ${lib} " to linker")
    target_link_libraries(Whispercpp INTERFACE Whispercpp::${lib})
  endforeach(lib ${WHISPER_LIBRARIES})
  if(${ACCELERATION} STREQUAL "cpu-blas")
    target_link_libraries(Whispercpp INTERFACE ${CBLAS_LIBRARIES})
  elseif(${ACCELERATION} STREQUAL "cuda")
    target_link_libraries(Whispercpp INTERFACE CUDA::cudart CUDA::cublas CUDA::cublasLt CUDA::cuda_driver)
  elseif(${ACCELERATION} STREQUAL "vulkan")
    target_link_libraries(Whispercpp INTERFACE Vulkan::Vulkan)
  endif()
endif()
