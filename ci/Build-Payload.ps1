#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'utils/Common.ps1')
Assert-FreeDiskSpace 'Build-Payload'

# Build the client only; package it after signing.
Use-BuildTools
Remove-Item Env:CARGO_BUILD_TARGET -ErrorAction SilentlyContinue
Remove-Item Env:CARGO_TARGET_DIR -ErrorAction SilentlyContinue
powershell -NoProfile -File scripts/windows/build-rustdesk-appname.ps1 -AppName ProVDesk -EditorName WanPulse -OutputDir artifacts\ci-payload -SkipPortablePack
Assert-NativeSuccess 'Compilation du payload'
$script:payload = (Resolve-Path artifacts/ci-payload).Path
if (-not (Test-Path -LiteralPath "$payload/ProVDesk.exe" -PathType Leaf)) { throw 'ProVDesk.exe absent du payload.' }
$links = @(Get-ChildItem -LiteralPath $payload -Recurse -Force |
    Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
if ($links.Count -gt 0) { throw 'Liens/reparse points interdits dans le payload.' }

# Archive dependency resolutions and the submodule patch used for this build.
Copy-Item "$root/Cargo.lock" "$work/Cargo.lock"
Copy-Item "$root/flutter/pubspec.lock" "$work/pubspec.lock"
Copy-Item "$root/vcpkg.json" "$work/vcpkg.json"
Copy-Item "$root/scripts/windows/provdesk-hbb-common.patch" "$work/provdesk-hbb-common.patch"
