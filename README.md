# ProVDesk

ProVDesk is WanPulse's remote desktop client, based on
[RustDesk](https://github.com/rustdesk/rustdesk). This repository contains the
product sources, Windows customizations and build and signing pipeline.

## Product behavior

- Windows x64 client with a ProVDesk interface and installer.
- Configurable ID, relay and API servers, with no deployment-specific servers
  or keys embedded in the build. An ID server must be configured.
- Enforced WebSocket transport; domain endpoints use `wss://`.
- Connection links use `provdesk://`; `rustdesk://` associations owned by another
  application are preserved.
- Default installation in `C:\Program Files\WanPulse\ProVDesk`, respecting
  registered installations and custom installation paths.

The delivery scope of this CI is **Windows x64**. RustDesk's cross-platform code
remains present. See the [macOS packaging section](PROVDESK.md#reproduce-the-macos-operator-installer)
for packaging instructions and their current availability.

## Documentation

- [Product behavior and development builds](PROVDESK.md)
- [Build, signing and publication](ci/README.en.md)
- [Compilation, signature et publication — français](ci/README.md)
- [AGPL-3.0 license](LICENCE)

The multilingual `docs/README-*.md` pages describe upstream RustDesk.
The guides above document ProVDesk.

## Build and validate

Sources and CI are versioned together. Bitbucket builds the selected branch's
commit on a Windows runner with the WanPulse signing framework.
A push to `master` automatically runs the build, signing and publication pipeline.
The same step is available manually as `provdesk-build-sign-package` on any branch.
Publication depends only on the branch; no publication parameter is required.

| Branch | Output |
| --- | --- |
| `master` | Signed GitHub release, then final EXE published to SMB; Bitbucket artifacts retained |
| Other branches | Signed Bitbucket artifacts only; no GitHub or SMB publication |

GitHub releases contain `ProVDesk-<version>-windows-x86_64.exe`, its `.sha256` and `build.json`,
with a `provdesk-<version>-build.<number>` tag pointing to the built commit.
GitHub and SMB preflight checks run only on `master`. GitHub publication also requires
GitHub CLI and an organization-owned GitHub App with a secured private key;
CI generates temporary installation tokens. See the CI guide. Upstream GitHub Actions
workflows are separate from this Bitbucket delivery process.

The installer is available as `out/ProVDesk.exe`, alongside its SHA-256,
`build.json` and verification reports. The manifest identifies the built commit.
Validate installation, upgrades and remote sessions in a VM before distribution.

## Contributing

Clone this repository with its submodules (`git clone --recurse-submodules <REPOSITORY_URL>`).
Read the [development guidelines](AGENTS.md) and CI guides before changing sources
or dependencies. The CI guide explains how to configure one clone to push to both
GitHub and Bitbucket.

ProVDesk retains copyright notices from RustDesk and its dependencies.
Make the corresponding sources, patches and license available with every
distributed binary.
