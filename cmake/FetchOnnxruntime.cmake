include(FetchContent)

set(CUSTOM_ONNXRUNTIME_URL
    ""
    CACHE STRING "URL of a downloaded ONNX Runtime tarball")

set(CUSTOM_ONNXRUNTIME_HASH
    ""
    CACHE STRING "Hash of a downloaded ONNX Runtime tarball")

set(Onnxruntime_VERSION "1.23.1")

if(CUSTOM_ONNXRUNTIME_URL STREQUAL "")
  set(USE_PREDEFINED_ONNXRUNTIME ON)
else()
  if(CUSTOM_ONNXRUNTIME_HASH STREQUAL "")
    message(FATAL_ERROR "Both of CUSTOM_ONNXRUNTIME_URL and CUSTOM_ONNXRUNTIME_HASH must be present!")
  else()
    set(USE_PREDEFINED_ONNXRUNTIME OFF)
  endif()
endif()

if(USE_PREDEFINED_ONNXRUNTIME)
  set(Onnxruntime_BASEURL "https://github.com/microsoft/onnxruntime/releases/download/v${Onnxruntime_VERSION}")

  if(APPLE)
    set(Onnxruntime_URL "${Onnxruntime_BASEURL}/onnxruntime-osx-universal2-${Onnxruntime_VERSION}.tgz")
    set(Onnxruntime_HASH SHA256=e9fcd200bcf69377cc2c15e529368ca840d625669f34b1cf296a56b175665fc2)
  elseif(MSVC)
    set(Onnxruntime_URL "${Onnxruntime_BASEURL}/onnxruntime-win-x64-${Onnxruntime_VERSION}.zip")
    set(OOnnxruntime_HASH SHA256=d57817ee1e1aec8a7b4973ded0536f9be19ce0aa2152ff06a07952ed44790ed7)
  else()
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
      set(Onnxruntime_URL "${Onnxruntime_BASEURL}/onnxruntime-linux-aarch64-${Onnxruntime_VERSION}.tgz")
      set(Onnxruntime_HASH SHA256=263267fa063c1a86d755268f492eabbc62887542c4a9417a21d628219805061a)
    else()
      set(Onnxruntime_URL "${Onnxruntime_BASEURL}/onnxruntime-linux-x64-gpu-${Onnxruntime_VERSION}.tgz")
      set(Onnxruntime_HASH SHA256=d759646b084888ded846f3be36aaadea24b62a19accba2d64ff9c2e3fb714a62)
    endif()
  endif()
else()
  set(Onnxruntime_URL "${CUSTOM_ONNXRUNTIME_URL}")
  set(Onnxruntime_HASH "${CUSTOM_ONNXRUNTIME_HASH}")
endif()

FetchContent_Declare(
  onnxruntime
  URL ${Onnxruntime_URL}
  URL_HASH ${Onnxruntime_HASH})
FetchContent_MakeAvailable(onnxruntime)

if(APPLE)
  set(Onnxruntime_LIB "${onnxruntime_SOURCE_DIR}/lib/libonnxruntime.${Onnxruntime_VERSION}.dylib")
  target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE "${Onnxruntime_LIB}")
  target_include_directories(${CMAKE_PROJECT_NAME} SYSTEM PUBLIC "${onnxruntime_SOURCE_DIR}/include")
  target_sources(${CMAKE_PROJECT_NAME} PRIVATE "${Onnxruntime_LIB}")
  set_property(SOURCE "${Onnxruntime_LIB}" PROPERTY MACOSX_PACKAGE_LOCATION Frameworks)
  source_group("Frameworks" FILES "${Onnxruntime_LIB}")
  # add a codesigning step
  add_custom_command(
    TARGET "${CMAKE_PROJECT_NAME}"
    PRE_BUILD VERBATIM
    COMMAND /usr/bin/codesign --force --verify --verbose --sign "${CODESIGN_IDENTITY}" "${Onnxruntime_LIB}")
  add_custom_command(
    TARGET "${CMAKE_PROJECT_NAME}"
    POST_BUILD
    COMMAND
      ${CMAKE_INSTALL_NAME_TOOL} -change "@rpath/libonnxruntime.${Onnxruntime_VERSION}.dylib"
      "@loader_path/../Frameworks/libonnxruntime.${Onnxruntime_VERSION}.dylib" $<TARGET_FILE:${CMAKE_PROJECT_NAME}>)
elseif(MSVC)
  add_library(Ort INTERFACE)
  set(Onnxruntime_LIB_NAMES onnxruntime;onnxruntime_providers_shared)
  foreach(lib_name IN LISTS Onnxruntime_LIB_NAMES)
    add_library(Ort::${lib_name} SHARED IMPORTED)
    set_target_properties(Ort::${lib_name} PROPERTIES IMPORTED_IMPLIB ${onnxruntime_SOURCE_DIR}/lib/${lib_name}.lib)
    set_target_properties(Ort::${lib_name} PROPERTIES IMPORTED_LOCATION ${onnxruntime_SOURCE_DIR}/lib/${lib_name}.dll)
    set_target_properties(Ort::${lib_name} PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${onnxruntime_SOURCE_DIR}/include)
    target_link_libraries(Ort INTERFACE Ort::${lib_name})
    install(FILES ${onnxruntime_SOURCE_DIR}/lib/${lib_name}.dll DESTINATION "obs-plugins/64bit")
  endforeach()

  target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE Ort)

else()
  set(Onnxruntime_LINK_LIBS "${onnxruntime_SOURCE_DIR}/lib/libonnxruntime.so.${Onnxruntime_VERSION}")
  set(Onnxruntime_ADDITIONAL_LIBS
      "${onnxruntime_SOURCE_DIR}/lib/libonnxruntime_providers_shared.so"
      "${onnxruntime_SOURCE_DIR}/lib/libonnxruntime.so" "${onnxruntime_SOURCE_DIR}/lib/libonnxruntime.so.1")
  if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
    set(Onnxruntime_INSTALL_LIBS ${Onnxruntime_LINK_LIBS} ${Onnxruntime_ADDITIONAL_LIBS})
  else()
    set(Onnxruntime_INSTALL_LIBS ${Onnxruntime_LINK_LIBS} ${Onnxruntime_ADDITIONAL_LIBS})
  endif()
  target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE ${Onnxruntime_LINK_LIBS})
  target_include_directories(${CMAKE_PROJECT_NAME} SYSTEM PUBLIC "${onnxruntime_SOURCE_DIR}/include")
  install(FILES ${Onnxruntime_INSTALL_LIBS} DESTINATION "${CMAKE_INSTALL_LIBDIR}/obs-plugins/${CMAKE_PROJECT_NAME}")
  set_target_properties(${CMAKE_PROJECT_NAME} PROPERTIES INSTALL_RPATH "$ORIGIN/${CMAKE_PROJECT_NAME}")
endif()
