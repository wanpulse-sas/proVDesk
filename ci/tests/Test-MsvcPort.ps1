#Requires -Version 5.1
param([Parameter(Mandatory = $true)][string]$CMakePath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../utils/MsvcPort.ps1')
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $repository ('work/msbuild-port-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$fixture/ci/utils", "$fixture/build-tools" | Out-Null
Copy-Item "$repository/ci/utils/MsvcPort.cmake" "$fixture/ci/utils/"
$configuration = [pscustomobject]@{
    InstallationPath = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools'
    V143TargetsPath = 'Z:/work/private targets/MSBuild/Microsoft/VC/v170/'
    V143Version = '14.44.35207'
}
Write-MsvcPortSelection "$fixture/build-tools/msbuild-selection.cmake" $configuration
$check = @'
cmake_minimum_required(VERSION 3.17)
include("${CMAKE_CURRENT_LIST_DIR}/ci/utils/MsvcPort.cmake")
provdesk_msvc_port_options(options)
list(LENGTH options count)
if(NOT count EQUAL 3)
    message(FATAL_ERROR "MSBuild arguments were split or lost: ${options}")
endif()
list(GET options 0 targets)
list(GET options 1 instance)
list(GET options 2 version)
if(NOT targets STREQUAL "/p:VCTargetsPath=Z:/work/private targets/MSBuild/Microsoft/VC/v170/"
   OR NOT instance STREQUAL "/p:VSInstallDir=C:/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/"
   OR NOT version STREQUAL "/p:VCToolsVersion=14.44.35207")
    message(FATAL_ERROR "Incorrect MSBuild selection: ${options}")
endif()
'@
[IO.File]::WriteAllText("$fixture/check.cmake", $check)
& $CMakePath -P "$fixture/check.cmake"
if ($LASTEXITCODE -ne 0) { throw 'MSBuild port option regression test failed.' }
Write-Host 'MSBuild port options preserve paths with spaces and the exact compiler version.'

# Check PowerShell -> CMake argument forwarding while replacing every native execution.
. (Join-Path $PSScriptRoot '../utils/BuildResources.ps1')
New-Item -ItemType Directory -Force -Path "$fixture/ci/probes" | Out-Null
foreach ($name in @('Test-MsvcPort.cmake', 'msbuild.vcxproj', 'main.cpp', 'probe.rc')) {
    Copy-Item "$repository/ci/probes/$name" "$fixture/ci/probes/"
}
$check = @'
cmake_minimum_required(VERSION 3.17)
set(PROVDESK_MSBUILD "${CMAKE_COMMAND}")
set(PROVDESK_EXPECTED_MSC_VER 1944)
function(execute_process)
    if("${ARGV1}" STREQUAL "${PROVDESK_MSBUILD}")
        set(args ${ARGV})
        foreach(required IN ITEMS "${EXPECTED_NODE_ARGUMENT}" /p:UseMultiToolTask=true /p:EnforceProcessCountAcrossBuilds=true)
            if(NOT required IN_LIST args)
                message(FATAL_ERROR "Missing native argument: ${required}")
            endif()
        endforeach()
        if(EXPECTED_NODE_ARGUMENT STREQUAL "/m")
            if("${args}" MATCHES "MultiProcMaxCount=")
                message(FATAL_ERROR "Automatic mode injected a numeric compiler cap")
            endif()
        elseif(NOT "/p:MultiProcMaxCount=3" IN_LIST args)
            message(FATAL_ERROR "Explicit compiler limit was lost")
        endif()
        set_property(GLOBAL PROPERTY native_arguments_checked TRUE)
    endif()
    set(result 0 PARENT_SCOPE)
endfunction()
include("${CMAKE_CURRENT_LIST_DIR}/ci/probes/Test-MsvcPort.cmake")
get_property(checked GLOBAL PROPERTY native_arguments_checked)
if(NOT checked)
    message(FATAL_ERROR "The direct MSBuild probe was not intercepted")
endif()
'@
[IO.File]::WriteAllText("$fixture/check-parallel.cmake", $check)
$savedLevel = $env:CMAKE_BUILD_PARALLEL_LEVEL
try {
    foreach ($level in @('', '3')) {
        $env:CMAKE_BUILD_PARALLEL_LEVEL = $level
        $arguments = @(Get-NativeParallelArguments)
        & $CMakePath "-DPROVDESK_MSBUILD_PARALLEL_ARGS=$($arguments -join ';')" "-DEXPECTED_NODE_ARGUMENT=$($arguments[0])" -P "$fixture/check-parallel.cmake"
        if ($LASTEXITCODE -ne 0) { throw 'Native parallel argument forwarding failed.' }
    }
} finally { $env:CMAKE_BUILD_PARALLEL_LEVEL = $savedLevel }
Write-Host 'Automatic and explicit MSBuild arguments passed through CMake; no compiler was invoked.'
