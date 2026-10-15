# ProVDesk Windows build

Modified from RustDesk by WanPulse on 2026-10-06. The functional changes are the
ProVDesk application name and enforced WebSocket transport. The original
copyright notices and AGPL-3.0 license in LICENCE are retained; the license and
its warranty disclaimer apply to this modified version.

Public source: https://github.com/wanpulse-sas/proVDesk
The ProVDesk About page offers this source link.

## Network configuration

WebSocket is enforced by the ProVDesk build. ID/rendezvous server, relay server,
API URL and server public key are configured normally at runtime; this build
contains no embedded values for those settings. Domain endpoints use secure
WebSocket (`wss://`) even when the API URL is empty.

The previous preconfigured release was withdrawn on 2026-10-06. Its matching
source remains in Git history for recipients who already downloaded it.

## Reproduce the Windows build

Clone the published ProVDesk source commit with `git clone --recurse-submodules`.
Use the upstream Windows build prerequisites (Rust/MSVC, Flutter, Python and
vcpkg): https://rustdesk.com/docs/en/dev/build/windows/
Install flutter_rust_bridge_codegen 1.80.1 (with its uuid feature) and
cargo-expand 1.0.95, as required by the upstream bridge workflow. The build
script regenerates the ignored bridge files before compiling.
Keep Cargo.lock and flutter/pubspec.lock from the same source commit.
Run from the repository root:

```powershell
./scripts/windows/build-rustdesk-appname.ps1
```

The script applies scripts/windows/provdesk-hbb-common.patch to the pinned
upstream submodule, enforces WebSocket, and produces the standalone
artifacts/ProVDesk/ProVDesk.exe together with LICENCE and this notice.
`-SkipPortablePack` instead produces a folder bundle; distribute the entire
folder, including its DLLs and data. The script preserves the caller's build
environment and restores Runner.rc after building.

## Before distributing binaries

Publish the exact matching modified source commit/tag to the public fork,
including this notice, the build script, the submodule patch and lockfiles.
Keep that source available without charge and provide its matching release link
alongside the binary. Update the About source URL to the matching release tag
when publishing a release. A local review build must not be represented as a
published-source release before those changes are publicly accessible.

Upstream source baseline: d5311574b (RustDesk 1.5.0).
Pinned hbb_common submodule: 229b904508364c8997aad0fb5af57effac859f60.
Review build toolchain: Rust 1.91.1, Flutter 3.24.5, Python 3.13, MSVC x64.


## Review scope and regression surface

- src/common.rs, build.rs: enforce only WebSocket when the build flag is enabled;
  rebuild when that flag changes. Server addresses and keys remain configurable.
- src/core_main.rs and src/flutter_ffi.rs: apply the WebSocket override after loading
  custom settings, before normal Windows application initialization.
- src/service.rs: the existing macOS service hook also applies these settings
  if a build enables the flag; this Windows build does not use that path.
- libs/hbb_common/build.rs and src/config.rs (tracked parent patch): choose the
  compile-time application name early enough for configuration/service paths.
- libs/hbb_common/src/websocket.rs (tracked parent patch): select secure
  WebSocket for domain endpoints in ProVDesk builds without requiring an API URL;
  ordinary builds and IP endpoint handling retain their existing behavior.
- src/platform/windows.rs: retain the existing ProVDesk installer naming and
  publisher changes.
- flutter/windows/runner/Runner.rc and libs/portable/build.rs: brand the Windows
  runner and standalone packer while retaining upstream copyright.
- flutter/lib/desktop/pages/desktop_setting_page.dart: add a ProVDesk-only source
  link in About; upstream notices and default RustDesk UI remain present.
- src/bridge_generated*.rs and flutter/lib/generated_bridge*.dart: regenerate
  the upstream bindings with flutter_rust_bridge_codegen 1.80.1 so the current
  cursor event is available to Flutter and the Windows build compiles. These
  generated files are included in the release source archive.
- scripts/windows/build-rustdesk-appname.ps1: configure the build, apply the
  pinned submodule patch and package the renamed executable with its notices.

The pre-existing flutter/pubspec.lock changes were preserved. No changes to
ManagerCore, AgentUbuntu or the server are part of this build preparation.
