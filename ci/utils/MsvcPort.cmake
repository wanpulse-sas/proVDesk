# Share the exact command-line properties between the libvpx port and its early probe.
function(provdesk_msvc_port_options output)
    include("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../build-tools/msbuild-selection.cmake")
    set(options
        "/p:VCTargetsPath=${PROVDESK_VCTARGETS_PATH}"
        "/p:VSInstallDir=${PROVDESK_VS_INSTALL_DIR}"
        "/p:VCToolsVersion=${PROVDESK_MSVC_VERSION}"
    )
    set("${output}" "${options}" PARENT_SCOPE)
endfunction()
