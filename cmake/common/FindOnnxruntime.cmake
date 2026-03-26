# Find the ONNX Runtime library

find_path(
  Onnxruntime_INCLUDE_DIR
  NAMES onnxruntime_cxx_api.h
  PATH_SUFFIXES include)

find_library(
  Onnxruntime_LIBRARY
  NAMES onnxruntime
  PATH_SUFFIXES lib lib64)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(Onnxruntime REQUIRED_VARS Onnxruntime_LIBRARY Onnxruntime_INCLUDE_DIR)

if(Onnxruntime_FOUND)
  set(Onnxruntime_LIBRARIES ${Onnxruntime_LIBRARY})
  if(NOT TARGET Onnxruntime::Onnxruntime)
    add_library(Onnxruntime::Onnxruntime UNKNOWN IMPORTED)
    set_target_properties(
      Onnxruntime::Onnxruntime PROPERTIES IMPORTED_LOCATION "${Onnxruntime_LIBRARY}" INTERFACE_INCLUDE_DIRECTORIES
                                                                                     "${Onnxruntime_INCLUDE_DIR}")
  endif()
endif()

mark_as_advanced(Onnxruntime_INCLUDE_DIR Onnxruntime_LIBRARY)
