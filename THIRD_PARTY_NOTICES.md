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

## Embedded components and release materials

ATRACDEnc also compiles Kiss FFT (Mark Borgerding and contributors, BSD-3-Clause),
libgha (Daniil Cherednik, BSD-2-Clause), and adapted FFmpeg ATRAC DSP code
(Maxim Poliakovski and other per-file authors, LGPL-2.1-or-later). Its remaining
component-specific copyright/license headers, including liboma, remain in source.
The libgha source includes additional Kiss FFT BSD/Unlicense notices.

Universal releases reproduce upstream license files, AUTHORS files and embedded
copyright/license comments in the readable `Licenses` directory. Complete exact
corresponding source, including the statically linked work using each library and
all dependency archives, is supplied both on the DMG and inside each app as
`Contents/Resources/CorrespondingSource.tar.gz`. See RELEASE_BUILD.md for modification,
relinking, installation and distribution instructions. GPL-3.0 and LGPL-2.1 texts
are available in Licenses/GPL-3.0.txt and Licenses/LGPL-2.1.txt. This packaging does
not impose extra restrictions on modification or reverse engineering for debugging
library modifications. No written-source-offer-only mechanism is used.
