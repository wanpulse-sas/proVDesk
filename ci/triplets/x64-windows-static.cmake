# Keep the pinned vcpkg defaults and select the installed v143 toolset explicitly.
include("${CMAKE_CURRENT_LIST_DIR}/../../build-tools/vcpkg/triplets/x64-windows-static.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../../build-tools/vcpkg-selection.cmake")
set(VCPKG_PLATFORM_TOOLSET v143)
