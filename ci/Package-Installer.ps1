#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
Assert-FreeDiskSpace 'Package-Installer'

Initialize-Signing
Use-BuildTools
Assert-SignedPayload
$signed = @((Get-Content -Encoding UTF8 "$work/payload-signed.json" -Raw | ConvertFrom-Json))
Remove-Item Env:CARGO_BUILD_TARGET -ErrorAction SilentlyContinue

# Build only the wrapper AFTER signing the client.
$env:RUSTDESK_APP_NAME = 'ProVDesk'
$env:RUSTDESK_EDITOR_NAME = 'WanPulse'
$env:CARGO_TARGET_DIR = Join-Path $root 'source\target'
Set-Location source
# Apply the fork workflow DPI adjustment to the wrapper only.
$manifestPatch = Join-Path $root 'ci/patches/wrapper-manifest.patch'
git apply --check $manifestPatch
Assert-NativeSuccess 'Verification patch manifeste wrapper'
git apply $manifestPatch
Assert-NativeSuccess 'Patch manifeste wrapper'
Copy-Item -LiteralPath $manifestPatch -Destination "$work/wrapper-manifest.patch"
python -c "import importlib.metadata; assert importlib.metadata.version('brotli') == '1.2.1', 'Brotli 1.2.1 requis'"
Assert-NativeSuccess 'Verification Brotli'
python libs/portable/generate.py -f $payload -o libs/portable -e "$payload\ProVDesk.exe" -t x86_64-pc-windows-msvc
Assert-NativeSuccess 'Packaging du payload signe'
$afterPackaging = @(Get-PayloadManifest)
if (Compare-Object $signed $afterPackaging -Property Path,SHA256,Length) { throw 'Payload modifie par le packaging.' }
Assert-SignedPayload
$finalExe = Join-Path $work 'ProVDesk.exe'
Copy-Item -LiteralPath target/x86_64-pc-windows-msvc/release/rustdesk-portable-packer.exe -Destination $finalExe
python "$root/ci/Verify-Package.py" "$root/source/libs/portable/data.bin" "$work/payload-signed.json" $finalExe
Assert-NativeSuccess 'Verification du contenu embarque'
