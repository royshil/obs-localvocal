include(ExternalProject)
include(FetchContent)

set(PREBUILT_WHISPERCPP_VERSION "0.0.10")
set(PREBUILT_WHISPERCPP_URL_BASE
    "https://github.com/locaal-ai/occ-ai-dep-whispercpp/releases/download/${PREBUILT_WHISPERCPP_VERSION}")

add_library(Whispercpp INTERFACE)

# Get the name for the whisper library file from the CMake component name
function(LIB_NAME COMPONENT WHISPER_COMPONENT_IMPORT_LIB)
  if((COMPONENT STREQUAL "Whisper") OR (COMPONENT STREQUAL "Whispercpp::Whisper"))
    set(WHISPER_COMPONENT_IMPORT_LIB
        whisper
        PARENT_SCOPE)
  elseif((COMPONENT STREQUAL "GGML") OR (COMPONENT STREQUAL "Whispercpp::GGML"))
    set(WHISPER_COMPONENT_IMPORT_LIB
        ggml
        PARENT_SCOPE)
  elseif((COMPONENT STREQUAL "WhisperCoreML") OR (COMPONENT STREQUAL "Whispercpp::WhisperCoreML"))
    set(WHISPER_COMPONENT_IMPORT_LIB
        whisper.coreml
        PARENT_SCOPE)
  else()
    string(REGEX REPLACE "(Whispercpp::)?(GGML)" "\\2" COMPONENT ${COMPONENT})
    string(REGEX REPLACE "GGML(.*)" "\\1" LIB_SUFFIX ${COMPONENT})
    string(TOLOWER ${LIB_SUFFIX} IMPORT_LIB_SUFFIX)
    set(WHISPER_COMPONENT_IMPORT_LIB
        "ggml-${IMPORT_LIB_SUFFIX}"
        PARENT_SCOPE)
  endif()
endfunction()

# Get library paths for Whisper libs
function(WHISPER_LIB_PATHS COMPONENT SOURCE_DIR WHISPER_STATIC_LIB_PATH WHISPER_SHARED_LIB_PATH)
  lib_name(${COMPONENT} WHISPER_COMPONENT_IMPORT_LIB)

  if(APPLE)
    set(STATIC_PATH ${SOURCE_DIR}/${CMAKE_INSTALL_LIBDIR})
    set(SHARED_PATH ${SOURCE_DIR}/${CMAKE_INSTALL_LIBDIR})
  elseif(WIN32)
    set(STATIC_PATH ${SOURCE_DIR}/${CMAKE_INSTALL_LIBDIR})
    set(SHARED_PATH ${SOURCE_DIR}/${CMAKE_INSTALL_BINDIR})
  else()
    set(STATIC_PATH ${SOURCE_DIR})
    set(SHARED_PATH ${SOURCE_DIR})
  endif()

  set(WHISPER_STATIC_LIB_PATH
      "${STATIC_PATH}/${CMAKE_STATIC_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_STATIC_LIBRARY_SUFFIX}"
      PARENT_SCOPE)
  set(WHISPER_SHARED_LIB_PATH
      "${SHARED_PATH}/${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_LIBRARY_SUFFIX}"
      PARENT_SCOPE)

  # Debugging
  set(WHISPER_STATIC_LIB_PATH
      "${STATIC_PATH}/${CMAKE_STATIC_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_STATIC_LIBRARY_SUFFIX}")
  set(WHISPER_SHARED_LIB_PATH
      "${SHARED_PATH}/${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_LIBRARY_SUFFIX}")
  message(STATUS "Whisper lib import path: " ${WHISPER_STATIC_LIB_PATH})
  message(STATUS "Whisper shared lib import path: " ${WHISPER_SHARED_LIB_PATH})
endfunction()

# Add a Whisper component to the build
function(ADD_WHISPER_COMPONENT COMPONENT LIB_TYPE SOURCE_DIR LIB_DIR)
  whisper_lib_paths(${COMPONENT} ${LIB_DIR} WHISPER_STATIC_LIB_PATH WHISPER_SHARED_LIB_PATH)

  add_library(${COMPONENT} ${LIB_TYPE} IMPORTED)
  if(LIB_TYPE STREQUAL STATIC)
    set_target_properties(${COMPONENT} PROPERTIES IMPORTED_LOCATION "${WHISPER_STATIC_LIB_PATH}")
  else()
    set_target_properties(${COMPONENT} PROPERTIES IMPORTED_LOCATION "${WHISPER_SHARED_LIB_PATH}")
    set_target_properties(${COMPONENT} PROPERTIES IMPORTED_IMPLIB "${WHISPER_STATIC_LIB_PATH}")
  endif()
  set_target_properties(${COMPONENT} PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${SOURCE_DIR}/include")
  target_link_libraries(Whispercpp INTERFACE ${COMPONENT})
endfunction()

function(ADD_WHISPER_RUNTIME_MODULE COMPONENT SOURCE_DIR LIB_DIR)
  whisper_lib_paths(${COMPONENT} ${LIB_DIR} WHISPER_STATIC_LIB_PATH WHISPER_SHARED_LIB_PATH)

  add_library(${COMPONENT} SHARED IMPORTED)
  set_target_properties(${COMPONENT} PROPERTIES IMPORTED_LOCATION "${WHISPER_SHARED_LIB_PATH}")
  set_target_properties(${COMPONENT} PROPERTIES IMPORTED_IMPLIB "${WHISPER_STATIC_LIB_PATH}")
  set_target_properties(${COMPONENT} PROPERTIES IMPORTED_NO_SONAME TRUE)
  set_target_properties(${COMPONENT} PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${SOURCE_DIR}/include")
endfunction()

if(APPLE)
  # check the "MACOS_ARCH" env var to figure out if this is x86 or arm64
  if($ENV{MACOS_ARCH} STREQUAL "x86_64")
    set(WHISPER_CPP_HASH "037da503f9ab1c18d530f49698ef805307358eb26bd833c285fb4f5bee32d511")
    list(
      APPEND
      WHISPER_RUNTIME_MODULES
      GGMLCPU-X64
      GGMLCPU-SSE42
      GGMLCPU-SANDYBRIDGE
      GGMLCPU-HASWELL
      GGMLCPU-SKYLAKEX
      GGMLCPU-ICELAKE
      GGMLCPU-ALDERLAKE
      GGMLCPU-SAPPHIRERAPIDS)
  elseif($ENV{MACOS_ARCH} STREQUAL "arm64")
    set(WHISPER_CPP_HASH "384984ce0e2fd21ae1a45ea53943259570d64ff186c595b35854ff357eb0fa67")
    list(APPEND WHISPER_RUNTIME_MODULES GGMLCPU)
  else()
    message(
      FATAL_ERROR
        "The MACOS_ARCH environment variable is not set to a valid value. Please set it to either `x86_64` or `arm64`")
  endif()
  set(WHISPER_CPP_URL
      "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-macos-$ENV{MACOS_ARCH}-${PREBUILT_WHISPERCPP_VERSION}.tar.gz")

  set(WHISPER_LIBRARIES Whisper GGML GGMLBase)
  list(APPEND WHISPER_RUNTIME_MODULES WhisperCoreML GGMLMetal GGMLBlas)
  set(WHISPER_DEPENDENCY_LIBRARIES "-framework Accelerate" "-framework CoreML" "-framework Metal" ${BLAS_LIBRARIES})
  set(WHISPER_LIBRARY_TYPE SHARED)

  FetchContent_Declare(
    whispercpp_fetch
    URL ${WHISPER_CPP_URL}
    URL_HASH SHA256=${WHISPER_CPP_HASH})
  FetchContent_MakeAvailable(whispercpp_fetch)

  add_compile_definitions(LOCALVOCAL_WITH_COREML)

  set(WHISPER_SOURCE_DIR ${whispercpp_fetch_SOURCE_DIR})
  set(WHISPER_LIB_DIR ${whispercpp_fetch_SOURCE_DIR})
elseif(WIN32)
  if(NOT DEFINED ACCELERATION)
    message(FATAL_ERROR "ACCELERATION is not set. Please set it to either `cpu`, `cuda`, `vulkan` or `hipblas`")
  endif()

  set(WHISPER_LIBRARIES Whisper GGML GGMLBase)
  set(WHISPER_RUNTIME_MODULES
      GGMLCPU-X64
      GGMLCPU-SSE42
      GGMLCPU-SANDYBRIDGE
      GGMLCPU-HASWELL
      GGMLCPU-SKYLAKEX
      GGMLCPU-ICELAKE
      GGMLCPU-ALDERLAKE
      GGMLBlas
      GGMLVulkan)
  set(WHISPER_LIBRARY_TYPE SHARED)

  set(ARCH_PREFIX "")
  set(ACCELERATION_PREFIX "-${ACCELERATION}")
  set(WHISPER_CPP_URL
      "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-windows${ARCH_PREFIX}${ACCELERATION_PREFIX}-${PREBUILT_WHISPERCPP_VERSION}.zip"
  )
  if(${ACCELERATION} STREQUAL "generic")
    set(WHISPER_CPP_HASH "f52ee0dc9d24bdc524058fe025d0caeb63d978a5909fb58ff2d247e7327b9033")
  elseif(${ACCELERATION} STREQUAL "nvidia")
    set(WHISPER_CPP_HASH "7c07c6d9638bbcfe7346a6287dd803ae4806e381ef5e127dac3e4f5b62f9bbb2")
    list(APPEND WHISPER_RUNTIME_MODULES GGMLCUDA)
  elseif(${ACCELERATION} STREQUAL "amd")
    set(WHISPER_CPP_HASH "6add4ae9c23058801fe0aac31d9a30aa202a527d860c42e4b382b164ce3cc81c")
    list(APPEND WHISPER_RUNTIME_MODULES GGMLHip)
  else()
    message(
      FATAL_ERROR
        "The ACCELERATION environment variable is not set to a valid value. Please set it to either `generic`, `nvidia` or `amd`"
    )
  endif()

  FetchContent_Declare(
    whispercpp_fetch
    URL ${WHISPER_CPP_URL}
    URL_HASH SHA256=${WHISPER_CPP_HASH}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  FetchContent_MakeAvailable(whispercpp_fetch)

  set(WHISPER_SOURCE_DIR ${whispercpp_fetch_SOURCE_DIR})
  set(WHISPER_LIB_DIR ${whispercpp_fetch_SOURCE_DIR})
  set(WHISPER_DEPENDENCY_LIBRARIES "${whispercpp_fetch_SOURCE_DIR}/lib/libopenblas.lib")

  # glob all dlls in the bin directory and install them
  file(GLOB WHISPER_DLLS ${whispercpp_fetch_SOURCE_DIR}/bin/*.dll)
  install(FILES ${WHISPER_DLLS} DESTINATION "obs-plugins/64bit")
else()
  # Linux

  # Enable ccache if available
  find_program(CCACHE_PROGRAM ccache QUIET)
  if(CCACHE_PROGRAM)
    message(STATUS "Found ccache: ${CCACHE_PROGRAM}")
    set(CMAKE_C_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
    set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
  endif()

  if(CI)
    set(WHISPER_LIBRARIES Whisper GGML GGMLBase)
    list(APPEND WHISPER_DEPENDENCY_LIBRARIES Vulkan::Vulkan ${BLAS_LIBRARIES} OpenCL::OpenCL)
    list(
      APPEND
      WHISPER_RUNTIME_MODULES
      GGMLCPU-X64
      GGMLCPU-SSE42
      GGMLCPU-SANDYBRIDGE
      GGMLCPU-HASWELL
      GGMLCPU-SKYLAKEX
      GGMLCPU-ICELAKE
      GGMLCPU-ALDERLAKE
      GGMLCPU-SAPPHIRERAPIDS
      GGMLBlas
      GGMLVulkan
      GGMLOpenCL)

    set(ARCH_PREFIX "-x86_64")
    set(ACCELERATION_PREFIX "-${ACCELERATION}")
    set(WHISPER_CPP_URL
        "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-linux${ARCH_PREFIX}${ACCELERATION_PREFIX}-Release.tar.gz")
    if(${ACCELERATION} STREQUAL "generic")
      set(WHISPER_CPP_HASH "f5eb433c251086facb9ccee4bcc17f66bbd753dbbe797668e84e900ee0eb0276")
    elseif(${ACCELERATION} STREQUAL "nvidia")
      set(WHISPER_CPP_HASH "b251aa7e9c19da85a4eac8425316b1c4dce95f0e6f07649a22586ef00c1c673d")
      list(APPEND WHISPER_RUNTIME_MODULES GGMLCUDA)
    elseif(${ACCELERATION} STREQUAL "amd")
      set(WHISPER_CPP_HASH "b2228efb575fda12a2aba6d6413ca4c9653091427a2ddd752f34feb5975be25b")
      list(APPEND WHISPER_RUNTIME_MODULES GGMLHip)
    else()
      message(
        FATAL_ERROR
          "The ACCELERATION environment variable is not set to a valid value. Please set it to either `generic`, `nvidia` or `amd`"
      )
    endif()

    FetchContent_Declare(
      whispercpp_fetch
      URL ${WHISPER_CPP_URL}
      URL_HASH SHA256=${WHISPER_CPP_HASH}
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    FetchContent_MakeAvailable(whispercpp_fetch)

    message(STATUS "Whispercpp URL: ${WHISPER_CPP_URL}")
    message(STATUS "Whispercpp source dir: ${whispercpp_fetch_SOURCE_DIR}")
  else()
    # Source build
    if(${CMAKE_BUILD_TYPE} STREQUAL Release OR ${CMAKE_BUILD_TYPE} STREQUAL RelWithDebInfo)
      set(Whispercpp_BUILD_TYPE Release)
    else()
      set(Whispercpp_BUILD_TYPE Debug)
    endif()
    set(Whispercpp_Build_GIT_TAG "v1.8.2")
    set(WHISPER_EXTRA_CXX_FLAGS "-fPIC")
    set(WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS)
    set(WHISPER_LIBRARIES Whisper GGML GGMLBase)
    set(WHISPER_RUNTIME_MODULES GGMLBlas)
    set(WHISPER_DEPENDENCY_LIBRARIES ${BLAS_LIBRARIES})
    set(WHISPER_LIBRARY_TYPE SHARED)

    if(WHISPER_DYNAMIC_BACKENDS)
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON)
      list(
        APPEND
        WHISPER_RUNTIME_MODULES
        GGMLCPU-X64
        GGMLCPU-SSE42
        GGMLCPU-SANDYBRIDGE
        GGMLCPU-HASWELL
        GGMLCPU-SKYLAKEX
        GGMLCPU-ICELAKE
        GGMLCPU-ALDERLAKE
        GGMLCPU-SAPPHIRERAPIDS)
      add_compile_definitions(WHISPER_DYNAMIC_BACKENDS)
    else()
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_NATIVE=ON)
      list(APPEND WHISPER_RUNTIME_MODULES GGMLCPU)
    endif()

    # TODO: Add SYCL support

    # set(CMAKE_PREFIX_PATH "C:/Program Files/AMD/ROCm/6.1;$ENV{VULKAN_SDK}")
    set(HIP_PLATFORM amd)
    set(CMAKE_HIP_PLATFORM amd)
    set(CMAKE_HIP_ARCHITECTURES OFF)
    find_package(hip QUIET)
    find_package(hipblas QUIET)
    find_package(rocblas QUIET)
    if(hip_FOUND
       AND hipblas_FOUND
       AND rocblas_FOUND)
      message(STATUS "hipblas found, Libraries: ${hipblas_LIBRARIES}")
      set(WHISPER_ADDITIONAL_ENV "CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH};HIP_PLATFORM=${HIP_PLATFORM}")
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_HIP=ON -DGGML_HIP_ROCWMMA_FATTN=ON)
      list(APPEND WHISPER_LIBRARIES GGMLHip)
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES hip::host roc::rocblas roc::hipblas)
    endif()

    find_package(CUDAToolkit QUIET)
    if(CUDAToolkit_FOUND)
      message(STATUS "CUDA found, Libraries: ${CUDAToolkit_LIBRARIES}")
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=native)
      list(APPEND WHISPER_LIBRARIES GGMLCUDA)
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES CUDA::cudart CUDA::cublas CUDA::cublasLt CUDA::cuda_driver)
    endif()

    find_package(
      Vulkan
      COMPONENTS glslc
      QUIET)
    if(Vulkan_FOUND)
      message(STATUS "Vulkan found, Libraries: ${Vulkan_LIBRARIES}")
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_VULKAN=ON)
      list(APPEND WHISPER_LIBRARIES GGMLVulkan)
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES Vulkan::Vulkan)
    endif()

    find_package(OpenCL QUIET)
    find_package(Python3 QUIET)
    if(OpenCL_FOUND AND Python3_FOUND)
      message(STATUS "OpenCL found, Libraries: ${OpenCL_LIBRARIES}")
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_OPENCL=ON -DGGML_OPENCL_EMBED_KERNELS=ON
           -DGGML_OPENCL_USE_ADRENO_KERNELS=OFF)
      list(APPEND WHISPER_LIBRARIES GGMLOpenCL)
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES OpenCL::OpenCL)
    endif()

    foreach(component ${WHISPER_LIBRARIES})
      whisper_lib_paths(${component} ${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/obs-plugins/${CMAKE_PROJECT_NAME}
                        WHISPER_STATIC_LIB_PATH WHISPER_SHARED_LIB_PATH)
      list(APPEND WHISPER_BYPRODUCTS ${WHISPER_SHARED_LIB_PATH})
    endforeach(component ${WHISPER_LIBRARIES})

    # On Linux build a shared Whisper library
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
        ${CMAKE_GENERATOR} -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
        -DCMAKE_INSTALL_LIBDIR=${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/obs-plugins/${CMAKE_PROJECT_NAME}
        -DCMAKE_INSTALL_BINDIR=${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/obs-plugins/${CMAKE_PROJECT_NAME}
        -DCMAKE_BUILD_TYPE=${Whispercpp_BUILD_TYPE} -DCMAKE_GENERATOR_PLATFORM=${CMAKE_GENERATOR_PLATFORM}
        -DCMAKE_CXX_FLAGS=${WHISPER_EXTRA_CXX_FLAGS} -DCMAKE_C_FLAGS=${WHISPER_EXTRA_CXX_FLAGS}
        -DCMAKE_CUDA_FLAGS=${WHISPER_EXTRA_CXX_FLAGS} -DBUILD_SHARED_LIBS=ON -DWHISPER_BUILD_TESTS=OFF
        -DWHISPER_BUILD_EXAMPLES=OFF ${WHISPER_ADDITIONAL_CMAKE_ARGS})

    ExternalProject_Get_Property(Whispercpp_Build INSTALL_DIR)

    set(WHISPER_SOURCE_DIR ${INSTALL_DIR})
    set(WHISPER_LIB_DIR ${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/obs-plugins/${CMAKE_PROJECT_NAME})

    add_dependencies(Whispercpp Whispercpp_Build)
  endif()
endif()

foreach(lib ${WHISPER_LIBRARIES})
  message(STATUS "Adding " Whispercpp::${lib} " to build")
  add_whisper_component(Whispercpp::${lib} ${WHISPER_LIBRARY_TYPE} ${WHISPER_SOURCE_DIR} ${WHISPER_LIB_DIR})
endforeach(lib ${WHISPER_LIBRARIES})

foreach(lib ${WHISPER_RUNTIME_MODULES})
  message(STATUS "Adding " Whispercpp::${lib} " to build as runtime module")
  add_whisper_runtime_module(Whispercpp::${lib} ${WHISPER_SOURCE_DIR} ${WHISPER_LIB_DIR})
endforeach(lib ${WHISPER_LIBRARIES})

foreach(lib ${WHISPER_DEPENDENCY_LIBRARIES})
  message(STATUS "Adding dependency " ${lib} " to linker")
  target_link_libraries(Whispercpp INTERFACE ${lib})
endforeach(lib ${WHISPER_DEPENDENCY_LIBRARIES})

target_link_directories(${CMAKE_PROJECT_NAME} PRIVATE Whisper)
