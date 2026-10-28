# NetMD helper and third-party notices

Bootlegger's original application code retains its MIT license. The separate
BootleggerNetMD helper is distributed under GPL-3.0-or-later. Its complete source,
backend source, pinned dependency source archives, build script, and license notices
are included in the app under Contents/Resources/NetMDSources. Rebuild the helper
from that directory with `zsh scripts/build-netmd.sh` and Xcode command-line tools.

- netmd++ by Jo2003 and contributors: https://github.com/Jo2003/netmd_plusplus
  Revision 1da9cb60a676f4c9c441710501a7fc07b9f6b481. See Vendor/NetMD/LICENSE and
  per-file notices (which include LGPL-2.1-or-later notices).
- libusb 1.0.29: https://libusb.info/ — LGPL-2.1-or-later.
- libgpg-error 1.55: https://gnupg.org/software/libgpg-error/ — LGPL-2.1-or-later
  library; see source COPYING and COPYING.LIB for accompanying tools.
- libgcrypt 1.11.1: https://gnupg.org/software/libgcrypt/ — LGPL-2.1-or-later
  library; see source COPYING and COPYING.LIB for accompanying tools.

Upstream copyright notices and full license texts are retained. Source archives are
verified by SHA-256 before building. No proprietary Sony codec is redistributed.

The bundled BootleggerATRAC executable uses ATRACDEnc (LGPL-2.1-or-later), revision
cb170709f836cb43dc0312455188c791159d81dc, including libgha submodule revision
00a95243254cfb1e43b05888ebc68e9aa401507a. Complete source and per-file notices are
under Vendor/ATRACDEnc in NetMDSources. See https://github.com/dcherednik/atracdenc.
Its PCM-only libsndfile 1.2.2 dependency is built from a checksum-verified source
archive; its COPYING license is also bundled. See https://libsndfile.github.io/libsndfile/.
Rebuild using the included build-netmd.sh/build-atrac.sh scripts, Xcode tools and CMake.
The app has no runtime dependency on Homebrew, Node, or an encoding server.
