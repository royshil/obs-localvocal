include(ExternalProject)
include(FetchContent)

set(PREBUILT_WHISPERCPP_VERSION "0.0.11-2")
set(PREBUILT_WHISPERCPP_URL_BASE
    "https://github.com/locaal-ai/occ-ai-dep-whispercpp/releases/download/${PREBUILT_WHISPERCPP_VERSION}")

add_library(Whispercpp INTERFACE)

include(cmake/BuildWhispercppHelpers.cmake)

if(APPLE)
  add_compile_definitions(WHISPER_DYNAMIC_BACKENDS)

  # check the "MACOS_ARCH" env var to figure out if this is x86 or arm64
  if($ENV{MACOS_ARCH} STREQUAL "x86_64")
    set(WHISPER_CPP_HASH "e6fa37ea4f76d31a105dc557e90c41b9bb78a629bb3efa71b2c6f9ce029b77dd")

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
    set(WHISPER_CPP_HASH "4d18abb80aba27edc534a1720b2e4c552474d3380df0174465295f6d23d13589")
    list(APPEND WHISPER_RUNTIME_MODULES GGMLCPU-APPLE_M1 GGMLCPU-APPLE_M2_M3 GGMLCPU-APPLE_M4)
  else()
    message(
      FATAL_ERROR
        "The MACOS_ARCH environment variable is not set to a valid value. Please set it to either `x86_64` or `arm64`")
  endif()
  set(WHISPER_CPP_URL
      "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-macos-$ENV{MACOS_ARCH}-metalembedded-${PREBUILT_WHISPERCPP_VERSION}.tar.gz"
  )

  set(WHISPER_LIBRARIES Whisper Whisper_1 WhisperCoreML GGML GGMLBase)
  list(APPEND WHISPER_RUNTIME_MODULES GGMLMetal GGMLBlas)
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

  install_library_to_bundle(${whispercpp_fetch_SOURCE_DIR} libomp.dylib)
  # target_add_resource(${CMAKE_PROJECT_NAME} ${whispercpp_fetch_SOURCE_DIR}/bin/default.metallib)
elseif(WIN32)
  add_compile_definitions(WHISPER_DYNAMIC_BACKENDS)

  if(NOT DEFINED ACCELERATION)
    message(FATAL_ERROR "ACCELERATION is not set. Please set it to either `generic`, `nvidia`, or `amd`")
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
    set(WHISPER_CPP_HASH "43a69a80d6668fa4714cd145b7826deaa592b454c6f7da8ac71e7062114f1a7d")
  elseif(${ACCELERATION} STREQUAL "nvidia")
    set(WHISPER_CPP_HASH "0893975412bf720c76d4b92a910abdb8ebf7ac927c872e2bbb04db0b647f71fe")
    list(APPEND WHISPER_RUNTIME_MODULES GGMLCUDA)
  elseif(${ACCELERATION} STREQUAL "amd")
    set(WHISPER_CPP_HASH "656c242b658b20f8a60f8823b85385c6f03da17cfe401d6ef177ccd5749f2b0d")
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
  file(GLOB WHISPER_PDBS ${whispercpp_fetch_SOURCE_DIR}/bin/*.pdb)
  install(FILES ${WHISPER_PDBS} DESTINATION "obs-plugins/64bit")
else()
  # Linux

  # Enable ccache if available
  find_program(CCACHE_PROGRAM ccache QUIET)
  if(CCACHE_PROGRAM)
    message(STATUS "Found ccache: ${CCACHE_PROGRAM}")
    set(CMAKE_C_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
    set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
  endif()

  set(BLA_VENDOR OpenBLAS)
  find_package(BLAS REQUIRED)

  if(NOT LINUX_SOURCE_BUILD)
    add_compile_definitions(WHISPER_DYNAMIC_BACKENDS)
    set(WHISPER_LIBRARY_TYPE SHARED)
    set(WHISPER_LIBRARIES Whisper GGML GGMLBase)
    list(APPEND WHISPER_DEPENDENCY_LIBRARIES Vulkan::Vulkan BLAS::BLAS)
    if(NOT ${ACCELERATION} STREQUAL "nvidia")
      # NVidia CUDA has its own OpenCL library
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES OpenCL::OpenCL)
    endif()
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

    find_package(
      Vulkan
      COMPONENTS glslc
      REQUIRED)
    find_package(OpenCL REQUIRED)
    find_package(Python3 REQUIRED)

    set(ARCH_PREFIX "-x86_64")
    set(ACCELERATION_PREFIX "-${ACCELERATION}")
    set(WHISPER_CPP_URL
        "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-linux${ARCH_PREFIX}${ACCELERATION_PREFIX}-Release.tar.gz")
    if(${ACCELERATION} STREQUAL "generic")
      set(WHISPER_CPP_HASH "77555023b0fa15ce486ef56c6768d31f3b728feee64172e74dd8f8c811b62e10")
    elseif(${ACCELERATION} STREQUAL "nvidia")
      set(WHISPER_CPP_HASH "397ea1409a3cc92d049130b5f874bbd9c06325e5a56cd2d08b3d8706ce619b7b")
      list(APPEND WHISPER_RUNTIME_MODULES GGMLCUDA)

      # Find CUDA libraries and link against them
      set(CUDAToolkit_ROOT /usr/local/cuda-12.8/)
      find_package(CUDAToolkit REQUIRED)
      list(
        APPEND
        WHISPER_DEPENDENCY_LIBRARIES
        CUDA::cudart
        CUDA::cublas
        CUDA::cublasLt
        CUDA::cuda_driver
        CUDA::OpenCL)
    elseif(${ACCELERATION} STREQUAL "amd")
      set(WHISPER_CPP_HASH "7e3c45e92abe3fe4c08009c4842a13937d4a30285fa49116a7a75802f0e6e64a")
      list(APPEND WHISPER_RUNTIME_MODULES GGMLHip)

      # Find hip libraries and link against them
      set(CMAKE_PREFIX_PATH /opt/rocm-6.4.2/lib/cmake)
      set(HIP_PLATFORM amd)
      set(CMAKE_HIP_PLATFORM amd)
      set(CMAKE_HIP_ARCHITECTURES OFF)
      find_package(hip REQUIRED)
      find_package(hipblas REQUIRED)
      find_package(rocblas REQUIRED)
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES hip::host roc::rocblas roc::hipblas)
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

    set(WHISPER_SOURCE_DIR ${whispercpp_fetch_SOURCE_DIR})
    set(WHISPER_LIB_DIR ${whispercpp_fetch_SOURCE_DIR})

    file(GLOB WHISPER_SOS ${whispercpp_fetch_SOURCE_DIR}/lib/*${CMAKE_SHARED_LIBRARY_SUFFIX}*)
    install(FILES ${WHISPER_SOS} DESTINATION "${CMAKE_INSTALL_LIBDIR}/obs-plugins/obs-localvocal")
    file(GLOB WHISPER_BIN_SOS ${whispercpp_fetch_SOURCE_DIR}/bin/*${CMAKE_SHARED_LIBRARY_SUFFIX}*)
    install(FILES ${WHISPER_BIN_SOS} DESTINATION "${CMAKE_INSTALL_LIBDIR}/obs-plugins/obs-localvocal")
  else()
    # Source build
    if(${CMAKE_BUILD_TYPE} STREQUAL Release OR ${CMAKE_BUILD_TYPE} STREQUAL RelWithDebInfo)
      set(Whispercpp_BUILD_TYPE RelWithDebInfo)
    else()
      set(Whispercpp_BUILD_TYPE Debug)
    endif()
    set(Whispercpp_Build_GIT_TAG "v1.8.2")
    set(WHISPER_EXTRA_CXX_FLAGS "-fPIC")
    set(WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS)
    set(WHISPER_LIBRARIES Whisper GGML GGMLBase)

    set(WHISPER_DEPENDENCY_LIBRARIES ${BLAS_LIBRARIES})
    set(WHISPER_LIBRARY_TYPE SHARED)

    if(WHISPER_DYNAMIC_BACKENDS)
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON)
      list(
        APPEND
        WHISPER_RUNTIME_MODULES
        GGMLBlas
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
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_NATIVE=ON -DGGML_BACKEND_DL=OFF)
      list(APPEND WHISPER_LIBRARIES GGMLBlas GGMLCPU)
    endif()

    find_package(
      Vulkan
      COMPONENTS glslc
      QUIET)
    if(Vulkan_FOUND)
      message(STATUS "Vulkan found, Libraries: ${Vulkan_LIBRARIES}")
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_VULKAN=ON)
      if(WHISPER_DYNAMIC_BACKENDS)
        list(APPEND WHISPER_RUNTIME_MODULES GGMLVulkan)
      else()
        list(APPEND WHISPER_LIBRARIES GGMLVulkan)
      endif()
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES Vulkan::Vulkan)
    endif()

    find_package(OpenCL QUIET)
    find_package(Python3 QUIET)
    if(OpenCL_FOUND AND Python3_FOUND)
      message(STATUS "OpenCL found, Libraries: ${OpenCL_LIBRARIES}")
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_OPENCL=ON -DGGML_OPENCL_EMBED_KERNELS=ON
           -DGGML_OPENCL_USE_ADRENO_KERNELS=OFF)
      if(WHISPER_DYNAMIC_BACKENDS)
        list(APPEND WHISPER_RUNTIME_MODULES GGMLOpenCL)
      else()
        list(APPEND WHISPER_LIBRARIES GGMLOpenCL)
      endif()
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES OpenCL::OpenCL)
    endif()

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
      list(APPEND WHISPER_ADDITIONAL_ENV "CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH};HIP_PLATFORM=${HIP_PLATFORM}")
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_HIP=ON -DGGML_HIP_ROCWMMA_FATTN=ON)
      if(WHISPER_DYNAMIC_BACKENDS)
        list(APPEND WHISPER_RUNTIME_MODULES GGMLHip)
      else()
        list(APPEND WHISPER_LIBRARIES GGMLHip)
      endif()
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES hip::host roc::rocblas roc::hipblas)
    endif()

    find_package(CUDAToolkit QUIET)
    if(CUDAToolkit_FOUND)
      message(STATUS "CUDA found, Libraries: ${CUDAToolkit_LIBRARIES}")
      list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_CUDA=ON)

      if(WHISPER_BUILD_ALL_CUDA_ARCHITECTURES)
        list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DCMAKE_CUDA_ARCHITECTURES=all)
      else()
        list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DCMAKE_CUDA_ARCHITECTURES=native)
      endif()

      if(WHISPER_DYNAMIC_BACKENDS)
        list(APPEND WHISPER_RUNTIME_MODULES GGMLCUDA)
      else()
        list(APPEND WHISPER_LIBRARIES GGMLCUDA)
      endif()
      list(APPEND WHISPER_DEPENDENCY_LIBRARIES CUDA::cudart CUDA::cublas CUDA::cublasLt CUDA::cuda_driver)
    endif()

    foreach(component ${WHISPER_LIBRARIES})
      lib_name(${component} WHISPER_COMPONENT_IMPORT_LIB)
      list(
        APPEND
        WHISPER_BYPRODUCTS
        "${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/obs-plugins/${CMAKE_PROJECT_NAME}/${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_LIBRARY_SUFFIX}"
      )
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
endforeach(lib ${WHISPER_RUNTIME_MODULES})

foreach(lib ${WHISPER_DEPENDENCY_LIBRARIES})
  message(STATUS "Adding dependency " ${lib} " to linker")
  target_link_libraries(Whispercpp INTERFACE ${lib})
endforeach(lib ${WHISPER_DEPENDENCY_LIBRARIES})

target_link_directories(${CMAKE_PROJECT_NAME} PRIVATE Whisper)
