# ProVDesk desktop builds

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

## Reproduce the macOS operator installer

The manual **ProVDesk macOS installers** workflow
(`.github/workflows/provdesk-macos.yml`) builds native Apple silicon and Intel
review packages using the same ProVDesk source and network build flags.
On a Mac with the build prerequisites, run:

    python3 scripts/macos/build-provdesk.py

Output: `artifacts/ProVDesk-macos/ProVDesk-macos-arm64.pkg` or
`ProVDesk-macos-x86_64.pkg`, plus checksum and notices.
Both require macOS 12.3 or later and install `/Applications/ProVDesk.app`.
The package registers rustdesk:// for standard-client compatibility and retains
provdesk:// for older links.
This is an operator installation: it does not silently provision macOS
Accessibility/Screen Recording permissions or install a remote-host daemon.

The script leaves existing source paths/build behavior intact. It stages and
brands a copy of the built macOS bundle and restores temporary deployment-target
edits. It reuses the pinned hbb_common patch rather than introducing a second
transport implementation. Do not build concurrently in the same checkout.

By default the app is ad-hoc signed and the package is unsigned, intended only
for review. For distribution, use the script's `--sign-identity`,
`--installer-identity` and `--notary-profile` options with an already configured
Apple Developer keychain. Successful notarization and installation must be
verified on macOS before release.

The added workflow is manual only and uploads artifacts; it does not create a
release. No new Rust, Flutter or existing Windows runtime path is changed by
this build preparation.


## Shared URI scheme (2026-10-29)

ProVDesk now uses rustdesk:// as its primary launch URI while retaining the
ProVDesk application, service and configuration names. The Windows installer
registers the shared scheme alongside its existing provdesk:// registration.
The macOS packaging script registers both schemes. Existing provdesk:// launch
links remain accepted by the desktop client.

Installing both RustDesk and ProVDesk can change the OS-selected handler for
rustdesk://. ProVDesk's Windows uninstaller removes that registration only while
it points at its own installed executable; it does not restore an older handler.

Regression surface: src/common.rs selects the shared URI prefix for ProVDesk
only; src/platform/windows.rs registers/removes the compatibility handler;
flutter/lib/common.dart and flutter/lib/models/model.dart accept legacy links;
flutter/lib/desktop/pages/desktop_home_page.dart keeps upstream-update prompts
disabled for ProVDesk after the URI prefix is shared;
scripts/macos/build-provdesk.py declares both bundle URL schemes.
Other product names retain their original URI prefixes. No submodule revision,
remote session protocol, server address, key, or WebSocket policy changes.

## Windows UI customization (2026-11-05)

ProVDesk shows only the left home panel, expanded to fill the window, including
its connection status. Both incoming and outgoing connections remain enabled;
outgoing sessions can still be launched through rustdesk://, provdesk:// and
the existing command-line options. Settings remain accessible.

On Windows, an uninstalled main-window launch opens the installation page
instead of the home page, regardless of the executable name. The installer
hides Run without install. These are Flutter UI changes only; no Rust mode,
transport, service, installer engine or command-line behavior is changed.
The existing single-EXE packer still bundles the installer payload.

Regression surface: flutter/lib/main.dart selects the installer before starting
the normal main UI when ProVDesk is not installed; desktop_home_page.dart hides
the right panel and retains status on the left; install_page.dart hides the
portable-run action. Other application names keep their existing UI.

Build with the existing Windows script; output for this review is
artifacts/provdesk-1.5.0-20261105-left-panel/ProVDesk.exe. The user signs this
EXE after local validation, before its matching source and binary are published.

The About source link targets the matching release tag
provdesk-1.5.0-20261105-left-panel; publish that tag with the signed binary.

## Configured-server review (2026-11-05)

ProVDesk hides the home connection-state row. Without an explicitly configured
ID server it neither selects the built-in public rendezvous servers nor reuses
cached rendezvous addresses; a configured custom server is used normally. The
implicit public API fallback is also disabled. Incoming and outgoing modes are
unchanged, including explicitly supplied server addresses in connection links.
The Windows publisher and EXE company metadata default to WanPulse. The signer
shown by Windows after signing depends on the signing certificate.

Regression surface: desktop_home_page.dart hides status for ProVDesk only; the
existing hbb_common config patch bypasses cached/public defaults for ProVDesk
only; src/common.rs bypasses its implicit public API URL for ProVDesk only; the
Windows build script and Runner.rc set publisher/company metadata. The About
source link targets provdesk-1.5.0-20261105-configured-server. No submodule commit
revision, connection mode, configured endpoint or protocol changes are included.

## Windows installation directory (2026-11-06)

Fresh ProVDesk installations now default to the WanPulse subfolder beneath
the existing Program Files directory: C:\Program Files\WanPulse\ProVDesk
on 64-bit Windows. The existing ProgramFiles and 32-bit directory selection
remain in effect. A registered InstallLocation still takes precedence, so
existing installations and custom installation paths remain recognized.

Regression surface: src/platform/windows.rs adds the publisher folder only
when computing ProVDesk's default installation path. Registry-based path
lookup, service/configuration names and other application names are unchanged.
The About source link targets provdesk-1.5.0-20261106-wanpulse-path.
