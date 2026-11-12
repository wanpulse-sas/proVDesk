#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
Assert-FreeDiskSpace 'Complete-Payload'
Use-BuildTools
Initialize-Signing
$lock = Get-Content -Encoding UTF8 "$root/ci/dependencies.json" -Raw | ConvertFrom-Json

git init build-tools/topmost
Assert-NativeSuccess 'Init WindowInjection'
git -C build-tools/topmost remote add origin https://github.com/rustdesk-org/RustDeskTempTopMostWindow.git
Assert-NativeSuccess 'Remote WindowInjection'
git -C build-tools/topmost fetch --depth 1 origin $lock.topmostCommit
Assert-NativeSuccess 'Fetch WindowInjection'
git -C build-tools/topmost checkout --detach FETCH_HEAD
Assert-NativeSuccess 'Checkout WindowInjection'
$commit = git -C build-tools/topmost rev-parse HEAD
Assert-NativeSuccess 'Commit WindowInjection'
if ($commit -ne $lock.topmostCommit) { throw 'Commit WindowInjection inattendu.' }
$injectionOutput = Join-Path $root 'build-tools/window-injection-output'
$parallelArguments = @(Get-NativeParallelArguments)
& $env:MSBUILD_PATH "$root/build-tools/topmost/WindowInjection/WindowInjection.vcxproj" @parallelArguments /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v142 "/p:VCToolsVersion=$($script:visualStudio.V142Version)" "/p:VCTargetsPath=$($script:visualStudio.V142TargetsPath)" /p:TargetVersion=Windows10 "/p:OutDir=$($injectionOutput.Replace('\', '/'))/"
Assert-NativeSuccess 'Build WindowInjection (MSVC v142)'
Copy-Item "$injectionOutput/WindowInjection.dll" $payload
Copy-Item "$root/build-tools/topmost/LICENSE" "$payload/WindowInjection-LICENSE.txt"

$display = Join-Path (Get-LockedAsset 'display') 'usbmmidd_v2'
$displayDestination = New-Item -ItemType Directory -Path "$payload/usbmmidd_v2"
# Match the x64 workflow: omit Win32 binaries and obsolete device installers.
foreach ($file in @('usbmmidd.cat', 'usbmmIdd.inf', 'License.txt', 'idd_instructions.txt')) {
    Copy-Item -LiteralPath (Join-Path $display $file) -Destination $displayDestination.FullName
}
Copy-Item -LiteralPath "$display/x64" -Destination $displayDestination.FullName -Recurse
$printer = Get-LockedAsset 'printer'
New-Item -ItemType Directory -Path "$payload/drivers" | Out-Null
Copy-Item -LiteralPath "$printer/rustdesk_printer_driver_v4-1.4" -Destination "$payload/drivers/RustDeskPrinterDriver" -Recurse
$adapter = Get-LockedAsset 'adapter'
Copy-Item -LiteralPath "$adapter/printer_driver_adapter.dll" -Destination $payload
Assert-DriverCatalogs

foreach ($required in @('ProVDesk.exe', 'librustdesk.dll', 'flutter_windows.dll', 'dylib_virtual_display.dll',
    'WindowInjection.dll', 'printer_driver_adapter.dll', 'data/icudtl.dat', 'data/app.so', 'LICENCE', 'PROVDESK.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $payload $required) -PathType Leaf)) { throw "Payload incomplet : $required" }
}
if (-not (Test-Path -LiteralPath "$payload/data/flutter_assets" -PathType Container)) { throw 'Assets Flutter absents.' }
$beforeSigning = @(Get-PayloadManifest)
ConvertTo-Json -InputObject $beforeSigning -Depth 4 | Set-Content "$work/payload-unsigned.json" -Encoding UTF8
