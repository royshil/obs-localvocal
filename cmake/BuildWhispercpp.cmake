include(ExternalProject)
include(FetchContent)

set(PREBUILT_WHISPERCPP_VERSION "0.0.10-2")
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
function(WHISPER_LIB_PATHS COMPONENT SOURCE_DIR WHISPER_STATIC_LIB_PATH WHISPER_SHARED_LIB_PATH
         WHISPER_SHARED_MODULE_PATH)
  lib_name(${COMPONENT} WHISPER_COMPONENT_IMPORT_LIB)

  if(UNIX AND NOT APPLE)
    if(${LINUX_SOURCE_BUILD})
      set(STATIC_PATH ${SOURCE_DIR})
      set(SHARED_PATH ${SOURCE_DIR})
      set(SHARED_BIN_PATH ${SOURCE_DIR})
    else()
      set(STATIC_PATH ${SOURCE_DIR}/lib)
      set(SHARED_PATH ${SOURCE_DIR}/lib)
      set(SHARED_BIN_PATH ${SOURCE_DIR}/bin)
    endif()
  else()
    set(STATIC_PATH ${SOURCE_DIR}/${CMAKE_INSTALL_LIBDIR})
    set(SHARED_PATH ${SOURCE_DIR}/${CMAKE_INSTALL_LIBDIR})
    set(SHARED_BIN_PATH ${SOURCE_DIR}/${CMAKE_INSTALL_BINDIR})
  endif()

  set(WHISPER_STATIC_LIB_PATH
      "${STATIC_PATH}/${CMAKE_STATIC_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_STATIC_LIBRARY_SUFFIX}"
      PARENT_SCOPE)
  set(WHISPER_SHARED_LIB_PATH
      "${SHARED_PATH}/${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_LIBRARY_SUFFIX}"
      PARENT_SCOPE)
  set(WHISPER_SHARED_MODULE_PATH
      "${SHARED_BIN_PATH}/${CMAKE_SHARED_MODULE_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_MODULE_SUFFIX}"
      PARENT_SCOPE)

  # Debugging
  set(WHISPER_STATIC_LIB_PATH
      "${STATIC_PATH}/${CMAKE_STATIC_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_STATIC_LIBRARY_SUFFIX}")
  set(WHISPER_SHARED_LIB_PATH
      "${SHARED_PATH}/${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_LIBRARY_SUFFIX}")
  set(WHISPER_SHARED_MODULE_PATH
      "${SHARED_BIN_PATH}/${CMAKE_SHARED_MODULE_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_MODULE_SUFFIX}")
  message(STATUS "Whisper lib import path: " ${WHISPER_STATIC_LIB_PATH})
  message(STATUS "Whisper shared lib import path: " ${WHISPER_SHARED_LIB_PATH})
  message(STATUS "Whisper shared MODULE import path: " ${WHISPER_SHARED_MODULE_PATH})
endfunction()

# Add a Whisper component to the build
function(ADD_WHISPER_COMPONENT COMPONENT LIB_TYPE SOURCE_DIR LIB_DIR)
  whisper_lib_paths(${COMPONENT} ${LIB_DIR} WHISPER_STATIC_LIB_PATH WHISPER_SHARED_LIB_PATH WHISPER_SHARED_MODULE_PATH)
  lib_name(${COMPONENT} WHISPER_COMPONENT_IMPORT_LIB)

  if(APPLE AND (LIB_TYPE STREQUAL SHARED))
    target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE "${WHISPER_SHARED_LIB_PATH}")
    target_sources(${CMAKE_PROJECT_NAME} PRIVATE "${WHISPER_SHARED_LIB_PATH}")
    set_property(SOURCE "${WHISPER_SHARED_LIB_PATH}" PROPERTY MACOSX_PACKAGE_LOCATION Frameworks)
    source_group("Frameworks" FILES "${WHISPER_SHARED_LIB_PATH}")
    add_custom_command(
      TARGET "${CMAKE_PROJECT_NAME}"
      PRE_BUILD VERBATIM
      COMMAND /usr/bin/codesign --force --verify --verbose --sign "${CODESIGN_IDENTITY}" "${WHISPER_SHARED_LIB_PATH}")
    message(STATUS "lib name: ${WHISPER_COMPONENT_IMPORT_LIB}")
    if(${WHISPER_COMPONENT_IMPORT_LIB} STREQUAL whisper)
      set(DYLIB_NAME ${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}.1${CMAKE_SHARED_LIBRARY_SUFFIX})
    else()
      set(DYLIB_NAME ${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_LIBRARY_SUFFIX})
    endif()
    add_custom_command(
      TARGET "${CMAKE_PROJECT_NAME}"
      POST_BUILD
      COMMAND ${CMAKE_INSTALL_NAME_TOOL} -change "@rpath/${DYLIB_NAME}" "@loader_path/../Frameworks/${DYLIB_NAME}"
              $<TARGET_FILE:${CMAKE_PROJECT_NAME}>)
  else()
    add_library(${COMPONENT} ${LIB_TYPE} IMPORTED)

    if(LIB_TYPE STREQUAL STATIC)
      set_target_properties(${COMPONENT} PROPERTIES IMPORTED_LOCATION "${WHISPER_STATIC_LIB_PATH}")
    else()
      set_target_properties(${COMPONENT} PROPERTIES IMPORTED_LOCATION "${WHISPER_SHARED_LIB_PATH}")
      set_target_properties(${COMPONENT} PROPERTIES IMPORTED_IMPLIB "${WHISPER_STATIC_LIB_PATH}")
    endif()
    set_target_properties(${COMPONENT} PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${SOURCE_DIR}/include")
    target_link_libraries(Whispercpp INTERFACE ${COMPONENT})
  endif()
endfunction()

function(ADD_WHISPER_RUNTIME_MODULE COMPONENT SOURCE_DIR LIB_DIR)
  whisper_lib_paths(${COMPONENT} ${LIB_DIR} WHISPER_STATIC_LIB_PATH WHISPER_SHARED_LIB_PATH WHISPER_SHARED_MODULE_PATH)
  lib_name(${COMPONENT} WHISPER_COMPONENT_IMPORT_LIB)

  if(APPLE)
    target_include_directories(${CMAKE_PROJECT_NAME} SYSTEM PUBLIC "${SOURCE_DIR}/include")
    target_sources(${CMAKE_PROJECT_NAME} PRIVATE "${WHISPER_SHARED_MODULE_PATH}")
    set_property(SOURCE "${WHISPER_SHARED_MODULE_PATH}" PROPERTY MACOSX_PACKAGE_LOCATION Frameworks)
    source_group("Frameworks" FILES "${WHISPER_SHARED_MODULE_PATH}")
    # add a codesigning step
    add_custom_command(
      TARGET "${CMAKE_PROJECT_NAME}"
      PRE_BUILD VERBATIM
      COMMAND /usr/bin/codesign --force --verify --verbose --sign "${CODESIGN_IDENTITY}"
              "${WHISPER_SHARED_MODULE_PATH}")
    add_custom_command(
      TARGET "${CMAKE_PROJECT_NAME}"
      POST_BUILD
      COMMAND
        ${CMAKE_INSTALL_NAME_TOOL} -change "@rpath/${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_MODULE_SUFFIX}"
        "@loader_path/../Frameworks/${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_MODULE_SUFFIX}"
        $<TARGET_FILE:${CMAKE_PROJECT_NAME}>)
  else()
    add_library(${COMPONENT} SHARED IMPORTED)
    set_target_properties(${COMPONENT} PROPERTIES IMPORTED_LOCATION "${WHISPER_SHARED_LIB_PATH}")
    set_target_properties(${COMPONENT} PROPERTIES IMPORTED_IMPLIB "${WHISPER_STATIC_LIB_PATH}")
    set_target_properties(${COMPONENT} PROPERTIES IMPORTED_NO_SONAME TRUE)
    set_target_properties(${COMPONENT} PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${SOURCE_DIR}/include")
  endif()
endfunction()

if(APPLE)
  add_compile_definitions(WHISPER_DYNAMIC_BACKENDS)

  # check the "MACOS_ARCH" env var to figure out if this is x86 or arm64
  if($ENV{MACOS_ARCH} STREQUAL "x86_64")
    set(WHISPER_CPP_HASH "02446b1d508711b26cc778db48d5b8ef2dd7b0c98f5c9dfe39a1ad2ef9e3df07")
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
    set(WHISPER_CPP_HASH "ff2764b113e0f1fbafe0d8f86a339cd541d86a06d40a10eeac352050cc3be920")
    list(APPEND WHISPER_RUNTIME_MODULES GGMLCPU-APPLE_M1 GGMLCPU-APPLE_M2_M3 GGMLCPU-APPLE_M4)
  else()
    message(
      FATAL_ERROR
        "The MACOS_ARCH environment variable is not set to a valid value. Please set it to either `x86_64` or `arm64`")
  endif()
  set(WHISPER_CPP_URL
      "${PREBUILT_WHISPERCPP_URL_BASE}/whispercpp-macos-$ENV{MACOS_ARCH}-${PREBUILT_WHISPERCPP_VERSION}.tar.gz")

  set(WHISPER_LIBRARIES Whisper WhisperCoreML GGML GGMLBase)
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

  file(GLOB WHISPER_DYLIBS ${whispercpp_fetch_SOURCE_DIR}/lib/*.dylib)
  install(FILES ${WHISPER_DYLIBS} DESTINATION "${CMAKE_PROJECT_NAME}.plugin/Contents/Frameworks")
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
    set(WHISPER_CPP_HASH "affff7241d36aa09863d65fe5a2d581251a9955a4465186ffdec00c893abcaee")
  elseif(${ACCELERATION} STREQUAL "nvidia")
    set(WHISPER_CPP_HASH "2b07afba9ad3489e6f173be6be7ffde2625ba5c0d84af7e306308676cabf67a6")
    list(APPEND WHISPER_RUNTIME_MODULES GGMLCUDA)
  elseif(${ACCELERATION} STREQUAL "amd")
    set(WHISPER_CPP_HASH "9713220e1427b94f733255a25c2cf9f26577d2ce7eb55c48a6a0cc651313e9e5")
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
      set(WHISPER_CPP_HASH "5a4f3baf7d7e030f3e5a29d78fdd06f069fe472ad0f9ca93d40ed222052a3fe5")
    elseif(${ACCELERATION} STREQUAL "nvidia")
      set(WHISPER_CPP_HASH "a43dc8a44577e965caf9b0baaae74f30a9e00d99a296768021e7ccf0b9217878")
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
      set(WHISPER_CPP_HASH "1a7592da41493e57ead23c97a420f2db11a4fe31049c9b01cdb310bff05fdca1")
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
