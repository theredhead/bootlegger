# netmd++

Source: https://github.com/Jo2003/netmd_plusplus
Revision: 1da9cb60a676f4c9c441710501a7fc07b9f6b481
Retrieved: 2026-10-28

The include/ and src/ directories are copied from the revision above.
Local patch: CNetMdSecure::sendAudioTrack preserves the underlying transfer/commit
error codes instead of replacing every failure with NETMDERR_CMD_FAILED (-4). Upstream includes
LGPL-2.1-or-later file headers and a GPL-3.0 repository LICENSE. Bootlegger distributes
its NetMD helper under GPL-3.0-or-later, retaining all upstream notices and source.
The helper is a separate executable; the app's original MIT notices are retained.

Dependencies are pinned, checksum-verified source releases in scripts/build-netmd.sh:
libusb 1.0.29, libgpg-error 1.55, libgcrypt 1.11.1. See their source license files.
No Sony proprietary encoder or remote encoding service is used.

Local descriptor patch: trackCount, discFlags and discCapacity explicitly open and
close their respective descriptors, matching the standard NetMD request lifecycle.
This prevents state left by a prior query from causing RH1 rejection.

Local connection patch: openDevice claims the active interface without an
unconditional USB reset; probing must not disrupt recorder or media processing.

Local bulk-I/O patch: encrypted logical packets are sent through 16 KiB host USB
requests instead of one 1 MiB request. Larger requests timed out and detached the
connected RH1 on macOS. Also reject successful zero-byte writes to prevent a loop.

Local progress patch: bounded USB writes report acknowledged byte counts through a
scoped transfer observer, allowing continuous progress without changing packet data.

Local native-read patch: CNetMdApi::receiveSPTrack implements the RH1's standard
0x30 device-to-host command, with 64 KiB bulk reads, response/length validation
and a progress callback. Playback reads SP audio without entering factory mode,
changing protection flags or modifying the disc. Protocol references:
https://github.com/AlexanderS/linux-minidisc/blob/master/netmd/libnetmd.py
https://github.com/asivery/netmd-js/blob/master/src/netmd-interface.ts

Hardware verification: an RH1 SP track read successfully with 64 KiB USB requests;
16 KiB reads stalled. The decoded duration matched the TOC (187.06 seconds), and
the PCM signal was non-silent. Listening verification remains with the user.
