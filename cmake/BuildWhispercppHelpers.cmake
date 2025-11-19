# Get the name for the whisper library file from the CMake component name
function(LIB_NAME COMPONENT WHISPER_COMPONENT_IMPORT_LIB)
  if((COMPONENT STREQUAL "Whisper") OR (COMPONENT STREQUAL "Whispercpp::Whisper"))
    if(APPLE)
        set(WHISPER_COMPONENT_IMPORT_LIB
            whisper.1.8.2
            PARENT_SCOPE)
    else()
        set(WHISPER_COMPONENT_IMPORT_LIB
            whisper
            PARENT_SCOPE)
    endif()
  elseif((COMPONENT STREQUAL "Whisper_1") OR (COMPONENT STREQUAL "Whispercpp::Whisper_1"))
    set(WHISPER_COMPONENT_IMPORT_LIB
        whisper.1
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
  message(DEBUG "Whisper lib import path: " ${WHISPER_STATIC_LIB_PATH})
  message(DEBUG "Whisper shared lib import path: " ${WHISPER_SHARED_LIB_PATH})
  message(DEBUG "Whisper shared MODULE import path: " ${WHISPER_SHARED_MODULE_PATH})
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
    set(DYLIB_NAME ${CMAKE_SHARED_LIBRARY_PREFIX}${WHISPER_COMPONENT_IMPORT_LIB}${CMAKE_SHARED_LIBRARY_SUFFIX})
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

    # cmake-format off
    # Fix libomp.dylib load path
    # string(FIND ${WHISPER_COMPONENT_IMPORT_LIB} ggml-cpu IS_CPU_MODULE)
    # if(${IS_CPU_MODULE} EQUAL 0)
    #   message(STATUS "Fixing libomp name in ${WHISPER_COMPONENT_IMPORT_LIB}")
    #   add_custom_command(
    #   TARGET "${CMAKE_PROJECT_NAME}"
    #   PRE_BUILD
    #   COMMAND
    #     ${CMAKE_INSTALL_NAME_TOOL} -change "/usr/local/opt/libomp/lib/libomp.dylib"
    #     "@loader_path/../Frameworks/libomp.dylib"
    #     ${WHISPER_SHARED_MODULE_PATH})
    # endif()
    # cmake-format on

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
