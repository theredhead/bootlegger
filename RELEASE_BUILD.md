# Universal release and corresponding source

Run `./scripts/release.sh` from a checkout or the extracted corresponding-source
package. macOS 15+, Xcode with the macOS SDK, Python 3.9+, CMake and normal command
line build tools are required. Both architectures are cross-compiled; Rosetta is
not required to build the Intel slice on Apple Silicon. Optional Intel execution
checks require Rosetta or an Intel Mac.

The script freezes the current preferred source files before building. Both apps
and both native helpers contain arm64 and x86_64 slices. Dependency versions and
SHA-256 checksums are pinned in the native scripts. Each architecture has separate
source/configuration, object, CMake and installation directories. All app Mach-O
files are audited for both slices and for system-only dynamic dependencies.

The DMG contains both apps, a readable Licenses folder, a complete corresponding
source archive, SOURCE-MANIFEST.json and BUILD-MANIFEST.json. Each app also carries
that source archive, source manifest and license folder, so copying the app out of
the DMG preserves them. The archive includes the exact application/helper/vendor
sources, Xcode project, build scripts, tests, all four dependency source archives,
upstream license/copyright notices and dated local modification notices. No private
signing keys are required to rebuild or install a modified copy.

## Rebuild, modify and relink

1. Extract the source archive and open its Bootlegger directory.
2. Install/select the Xcode toolchain and CMake. General-purpose tools and Apple's
   system SDK/frameworks are prerequisites, not redistributed source dependencies.
3. Run `NETMD_FETCH=0 ./scripts/release.sh`. All vendor source archives are already
   present, verified, and sufficient to build without dependency downloads.
4. To rebuild helpers alone: `NETMD_ARCHS='arm64 x86_64' NETMD_FETCH=0 zsh scripts/build-netmd.sh`.
   This compiles the complete work using the libraries and relinks both helpers.
5. Modify the preferred sources or extracted dependency sources as desired. For
   dependency modifications, create an updated source archive and update its pin in
   build-netmd.sh/build-atrac.sh and release-support.py; or use an ordinary local
   native build against your modified dependency installation. Delete the matching
   `.build/NetMD/prefix-<architecture>-macos15` and architecture build directories
   when changing dependencies so a previous library is not reused.
6. To replace helpers in an existing app, copy the rebuilt BootleggerNetMD and
   BootleggerATRAC to `Contents/Helpers`, sign each with `codesign --force --sign -`,
   then sign the app with `codesign --force --sign - /path/to/App.app`.
   A fresh Xcode build performs these operations automatically.

Modification, rebuilding, relinking and reverse engineering for debugging library
modifications are permitted under the applicable bundled licenses; this release
adds no restriction on those rights. Normal macOS installation/security controls
still apply to locally rebuilt software.

## Distribution and repeatability

Distribute the whole DMG, or keep the source archive and license materials with any
separately distributed app. If offering binaries from a download page, keep the
matching source package equally accessible at no additional charge. Do not replace
it with a different revision or a link to an upstream repository alone.

The source manifest lists every source/archive SHA-256 and a content-derived
source ID, plus the originating commit and whether it included local changes.
The build manifest records Xcode/SDK/CMake versions, architectures, deployment
target and final Mach-O hashes. Keep the DMG, source archive, manifests, checksum
and build log together when publishing. Source archives normalize timestamps and
ownership. Signed binaries and DMGs have platform timestamps; the pipeline is
repeatable but does not claim bit-for-bit reproducibility of those outputs.

The default signing is ad-hoc. Set RELEASE_SIGN_IDENTITY to an installed Developer
ID identity for signing under that identity. Notarization is a separate Apple
account operation and is not performed by this script.
