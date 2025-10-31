include(ExternalProject)
include(FetchContent)

set(PREBUILT_WHISPERCPP_VERSION "0.0.9")
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

  set(WHISPER_STATIC_LIB_PATH
      "${SOURCE_DIR}/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_STATIC_LIBRARY_SUFFIX}"
      PARENT_SCOPE)
  set(WHISPER_SHARED_LIB_PATH
      "${SOURCE_DIR}/${CMAKE_INSTALL_BINDIR}/${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_LIBRARY_SUFFIX}"
      PARENT_SCOPE)

  # Debugging
  set(WHISPER_STATIC_LIB_PATH
      "${SOURCE_DIR}/${CMAKE_INSTALL_LIBDIR}/${CMAKE_STATIC_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_STATIC_LIBRARY_SUFFIX}"
  )
  set(WHISPER_SHARED_LIB_PATH
      "${SOURCE_DIR}/${CMAKE_INSTALL_BINDIR}/${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_LIBRARY_SUFFIX}"
  )
  message(STATUS "Whisper lib import path: " ${WHISPER_STATIC_LIB_PATH})
  message(STATUS "Whisper shared lib import path: " ${WHISPER_SHARED_LIB_PATH})
endfunction()

# Add a Whisper component to the build
function(ADD_WHISPER_COMPONENT COMPONENT LIB_TYPE SOURCE_DIR)
  whisper_lib_paths(${COMPONENT} ${SOURCE_DIR} WHISPER_STATIC_LIB_PATH WHISPER_SHARED_LIB_PATH
                    WHISPER_COMPONENT_IMPORT_LIB)

  add_library(${COMPONENT} ${LIB_TYPE} IMPORTED)
  if(LIB_TYPE STREQUAL STATIC)
    set_target_properties(${COMPONENT} PROPERTIES IMPORTED_LOCATION "${WHISPER_STATIC_LIB_PATH}")
  else()
    set_target_properties(${COMPONENT} PROPERTIES IMPORTED_LOCATION "${WHISPER_SHARED_LIB_PATH}")
    set_target_properties(${COMPONENT} PROPERTIES IMPORTED_IMPLIB "${WHISPER_STATIC_LIB_PATH}")
  endif()
  set_target_properties(${COMPONENT} PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${WHISPER_SOURCE_DIR}/include")
  target_link_libraries(Whispercpp INTERFACE ${COMPONENT})
endfunction()

if(APPLE)
  # check the "MACOS_ARCH" env var to figure out if this is x86 or arm64
  if($ENV{MACOS_ARCH} STREQUAL "x86_64")
    set(WHISPER_CPP_HASH "080e5a4005f689e5ea3d8b7eda2e5a6e6b3239e2c9c677a1ef5aaf8c4c843f1f")
  elseif($ENV{MACOS_ARCH} STREQUAL "arm64")
    set(WHISPER_CPP_HASH "d1059b49d3d545641f7de0cfc532c2a9d7f938e885333028196755ce4f41e6ab")
  else()
    message(
      FATAL_ERROR
        "The MACOS_ARCH environment variable is not set to a valid value. Please set it to either `x86_64` or `arm64`")
  endif()
  set(WHISPER_CPP_URL
      "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-macos-$ENV{MACOS_ARCH}-${PREBUILT_WHISPERCPP_VERSION}.tar.gz")

  set(WHISPER_LIBRARIES
      Whisper
      WhisperCoreML
      GGML
      GGMLBase
      GGMLCPU
      GGMLMetal
      GGMLBlas)
  set(WHISPER_DEPENDENCY_LIBRARIES "-framework Accelerate" "-framework CoreML" "-framework Metal" ${BLAS_LIBRARIES})
  set(WHISPER_LIBRARY_TYPE STATIC)

  FetchContent_Declare(
    whispercpp_fetch
    URL ${WHISPER_CPP_URL}
    URL_HASH SHA256=${WHISPER_CPP_HASH})
  FetchContent_MakeAvailable(whispercpp_fetch)

  add_compile_definitions(LOCALVOCAL_WITH_COREML)

  set(WHISPER_SOURCE_DIR ${whispercpp_fetch_SOURCE_DIR})
elseif(WIN32)
  if(NOT DEFINED ACCELERATION)
    message(FATAL_ERROR "ACCELERATION is not set. Please set it to either `cpu`, `cuda`, `vulkan` or `hipblas`")
  endif()

  set(WHISPER_LIBRARIES Whisper GGML GGMLBase GGMLCPU GGMLBlas)
  set(WHISPER_LIBRARY_TYPE SHARED)

  set(ARCH_PREFIX ${ACCELERATION})
  set(WHISPER_CPP_URL
      "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-windows-${ARCH_PREFIX}-${PREBUILT_WHISPERCPP_VERSION}.zip")
  if(${ACCELERATION} STREQUAL "cpu")
    set(WHISPER_CPP_HASH "c735eb53c1d0bac47a21590f290055e5769e886fa701ee8d3155cf9ebaa87988")
  elseif(${ACCELERATION} STREQUAL "cuda")
    set(WHISPER_CPP_HASH "35a0828c537ade5f5a634b5521853216b22881b3f5c8c67fa7b7f618b0dba559")
    list(APPEND WHISPER_LIBRARIES GGMLCUDA)
  elseif(${ACCELERATION} STREQUAL "hipblas")
    set(WHISPER_CPP_HASH "1c1b42fc432d09e7dca77e8d000d931a4551afaf45beb6669a8e467ee01ab319")
    list(APPEND WHISPER_LIBRARIES GGMLHip)
  elseif(${ACCELERATION} STREQUAL "vulkan")
    set(WHISPER_CPP_HASH "8a28a8cbf6ac7c811565d30bb220a6c26d1d8339a66d9f8957288129d767779b")
    list(APPEND WHISPER_LIBRARIES GGMLVulkan)
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

  set(WHISPER_SOURCE_DIR ${whispercpp_fetch_SOURCE_DIR})
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

  # if(CI) set(WHISPER_CPP_URL "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-linux-x86_64-vulkan-Release.tar.gz")
  # set(WHISPER_CPP_HASH "53262b76334af9ff68c37f5a77db665e49da355cb75d3e12d8eb302cb544d9e0")

  # set(WHISPER_LIBRARIES Whisper GGML GGMLBase GGMLCPU GGMLBlas GGMLVulkan) list(APPEND WHISPER_DEPENDENCY_LIBRARIES
  # Vulkan::Vulkan ${BLAS_LIBRARIES})

  # FetchContent_Declare( whispercpp_fetch URL ${WHISPER_CPP_URL} URL_HASH SHA256=${WHISPER_CPP_HASH}
  # DOWNLOAD_EXTRACT_TIMESTAMP TRUE) FetchContent_MakeAvailable(whispercpp_fetch)

  # message(STATUS "Whispercpp URL: ${WHISPER_CPP_URL}") message(STATUS "Whispercpp source dir:
  # ${whispercpp_fetch_SOURCE_DIR}")

  # foreach(lib ${WHISPER_LIBRARIES}) message(STATUS "Adding " ${lib} " to build") add_whisper_component(${lib} STATIC
  # TRUE ${whispercpp_fetch_SOURCE_DIR}) endforeach(lib ${WHISPER_LIBRARIES}) else() Source build
  if(${CMAKE_BUILD_TYPE} STREQUAL Release OR ${CMAKE_BUILD_TYPE} STREQUAL RelWithDebInfo)
    set(Whispercpp_BUILD_TYPE Release)
  else()
    set(Whispercpp_BUILD_TYPE Debug)
  endif()
  set(Whispercpp_Build_GIT_TAG "v1.8.2")
  set(WHISPER_EXTRA_CXX_FLAGS "-fPIC")
  set(WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS)
  set(WHISPER_LIBRARIES Whisper GGML GGMLBase GGMLCPU GGMLBlas)
  set(WHISPER_DEPENDENCY_LIBRARIES ${BLAS_LIBRARIES})
  set(WHISPER_LIBRARY_TYPE STATIC)

  # TODO: Add SYCL support

  if(WIN32)
    # Currently non-working attempt to make source builds with acceleration work on Windows
    set(WHISPER_EXTRA_CXX_FLAGS "/EHsc")
    FetchContent_Declare(
      BLAS
      # URL https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.30/OpenBLAS-0.3.30-x64.zip
      URL https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.30/OpenBLAS-0.3.30-x64-64.zip
      # URL_HASH SHA256=8b04387766efc05c627e26d24797ec0d4ed4c105ec14fa7400aa84a02db22b66
      URL_HASH SHA256=b4d8248ff14f8405ead4580f57503ffce240de3f6ad46409898f5bc0f989c5d2
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE OVERRIDE_FIND_PACKAGE)
    FetchContent_MakeAvailable(BLAS)
    set(BLAS_LIBRARIES ${blas_SOURCE_DIR}/lib/libopenblas.lib)
    list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DBLAS_LIBRARIES=${BLAS_LIBRARIES}
         -DBLAS_INCLUDE_DIRS=${blas_SOURCE_DIR}/include)
    set(WHISPER_ADDITIONAL_ENV "OPENBLAS_PATH=${blas_SOURCE_DIR}")

    add_library(BLAS SHARED IMPORTED)
    set_target_properties(BLAS PROPERTIES IMPORTED_LOCATION ${blas_SOURCE_DIR}/lib/libopenblas.dll.a)
  elseif(UNIX AND NOT APPLE)
    set(WHISPER_EXTRA_CXX_FLAGS "-fPIC")
  endif()

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
    list(APPEND WHISPER_ADDITIONAL_CMAKE_ARGS -DGGML_HIP=ON -DGGML_CUDA=OFF -DGGML_HIP_ROCWMMA_FATTN=ON)
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
    whisper_lib_paths(${component} <INSTALL_DIR> WHISPER_STATIC_LIB_PATH WHISPER_SHARED_LIB_PATH)
    list(APPEND WHISPER_BYPRODUCTS ${WHISPER_STATIC_LIB_PATH})
  endforeach(component ${WHISPER_LIBRARIES})

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

  set(WHISPER_SOURCE_DIR ${INSTALL_DIR})
endif()

foreach(lib ${WHISPER_LIBRARIES})
  message(STATUS "Adding " Whispercpp::${lib} " to build")
  add_whisper_component(Whispercpp::${lib} ${WHISPER_LIBRARY_TYPE} ${WHISPER_SOURCE_DIR})
endforeach(lib ${WHISPER_LIBRARIES})

foreach(lib ${WHISPER_DEPENDENCY_LIBRARIES})
  message(STATUS "Adding dependency " ${lib} " to linker")
  target_link_libraries(Whispercpp INTERFACE ${lib})
endforeach(lib ${WHISPER_DEPENDENCY_LIBRARIES})

add_dependencies(Whispercpp Whispercpp_Build)
