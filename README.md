# Bootlegger

A small native macOS utility for turning a local concert recording into individually
trimmed audio files, including tagged AAC/Apple Lossless albums for Apple Music. SwiftUI provides the editor; AppKit
handles document windows and AVKit/AVFoundation handle playback and media export.

## Build and run

Requires macOS 15 or later and Xcode with the macOS SDK. Development has been
verified with Xcode 27.1 on Apple Silicon. No third-party runtime dependencies.

Open `Bootlegger.xcodeproj`, select the Bootlegger scheme and My Mac, and Run.
The project uses local ad-hoc signing; no Apple developer account is required.

From the repository directory:

```sh
xcodebuild -project Bootlegger.xcodeproj -scheme Bootlegger \
  -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/Bootlegger.app
```

For an optimized app, build with `-configuration Release`; the result is
`.build/Build/Products/Release/Bootlegger.app`.

## Universal release disk image

```sh
./scripts/release.sh
```

Builds **all app targets and both native helpers for arm64 and x86_64** and creates
`.build/releases/Bootlegger-<version>-universal.dmg`. The DMG includes both apps,
an Applications shortcut, readable vendor licenses/copyright notices, exact complete
corresponding source and source/build manifests. Each app also contains the source
archive and license materials. A matching standalone source archive, SHA-256 checksum
file and full build log are published alongside the image.

Requires Xcode, CMake and Python 3.9+. Dependencies are pinned and checksum-verified;
set `NETMD_FETCH=0` to use only cached or bundled source archives. Builds run from a
frozen source snapshot, with isolated native build directories per architecture.
The release fails if any shipped Mach-O lacks either slice, depends on a third-party
runtime installation, or is missing required source/license materials.

Use `--output-dir /path/to/releases` for another output directory. Signing defaults
to ad-hoc; `RELEASE_SIGN_IDENTITY` selects an installed signing identity. See
[RELEASE_BUILD.md](RELEASE_BUILD.md) for rebuilding, modifying/relinking static
libraries, redistribution, and the limits of byte-for-byte reproducibility.

## Use

1. Choose **Import Recording**, drop an audio or video recording onto a project window, or drop it onto the
   Dock icon. MP4, MOV, M4V, MP3, M4A, WAV, AIFF, FLAC and other audio/video types are accepted when macOS can
   decode them. Bootlegger copies the recording, leaving the original unchanged.
   If a recording is already loaded, confirm replacement or cancel. Replacement keeps
   album metadata, song ranges and artwork; check ranges against the new recording.
   Failed imports preserve the previously loaded recording. Dock imports use the current
   project, or create one when no project is open. Multiple Dock files get separate projects.
   Use **File → New Project** (Command-N) for another concert in its own window.
   Playback uses Bootlegger's control bar; AVKit's floating controls are hidden.
2. Play or scrub to a song's beginning and choose **Add Song**. Each song has its own
   start and end; gaps and overlaps are supported. A new range defaults to up to
   three minutes, or the remaining video duration.
3. Edit start/end timestamps as seconds, `mm:ss.mmm`, or `hh:mm:ss.mmm`, then press
   Return or leave the field. Invalid timestamp syntax is shown in red. Up/down arrows nudge by 0.1 second. Drag
   timeline handles to trim, click a lane to seek, or double-click to add a song.
   The boundary arrow buttons copy the current playhead into the corresponding field.
4. Enter album title and artist, song titles, and optional artist overrides. Track
   numbers follow list order; use a song's ordering menu to move it earlier or later.
   The song play button previews its range; the end button seeks to its end boundary.
   Project edits support Undo/Redo (Command-Z / Shift-Command-Z).
5. Seek to a frame and choose **Artwork → Capture Frame** for album artwork. Optional year/date,
   genre, and venue are stored with the project. Venue exports as a comment.
6. **File → Save** (Command-S) writes a `.bootlegger` project bundle. **Open Project**
   (Command-O) reopens it. Multiple projects can stay open with independent playback
   and edits. Save explicitly; automatic saving/recovery is not implemented yet.
7. Choose **Export Album**, then a folder outside the project. Bootlegger creates a
   fresh album directory with songs named using the selected filename format. Existing exports are never overwritten.
   Cancelling or failing an export removes that operation's partial album directory.

## Fast marking and playback

Use these keys while no text box is being edited:

| Key | Action |
| --- | --- |
| S | Set the selected song's start to the playhead; create the first song if needed |
| E | Set the selected song's end to the playhead |
| Space | Play/pause |
| Left / Right | Seek backward/forward 10 seconds |
| Shift-Left / Shift-Right | Seek backward/forward 1 second |

Return or Escape commits an edited text field and explicitly returns focus to
playback; clicking outside an editable field does the same. Only the selected song
shows text boxes; other songs are plain selectable rows. Reversed, zero-length,
negative or out-of-recording boundary edits are rejected without changing the previous
range. A status message explains the rejection, and timestamp fields restore the valid
stored value. Timestamp fields keep their own editing/nudging behavior while focused.
When E finishes the last song in the list before the video's end, Bootlegger creates
and selects the next song at the same playhead, without interrupting playback.
Existing next songs are preserved. Use a song's number button to select it without
seeking. The timeline shows only the selected song.

The audio-level graph shows five seconds before/after the playhead by default;
its zoom slider reduces this to 0.1 second on each side. Click the graph to seek.
Levels are measured from decoded audio, taking the peak across channels. Nearby
audio is prepared in the background as needed. **Tools → Prescan Audio Levels**
reads the whole concert once and fills the in-memory cache for that open project.
Prescan progress and cancellation are available without blocking editing/playback.
The cache survives saving, and clears when the video changes or the project closes.

**File → Import Recording…** (Command-I) and **File → Export Album…** (Command-E)
provide the same actions as the toolbar.

Double-click the artwork to open its square crop editor. Drag to pan, use the zoom
slider or pinch, then choose **Apply**. **Cancel** discards the draft; **Remove Crop**
restores the original aspect ratio. Crop edits are undoable and saved with the project.
Selecting or capturing new artwork resets the crop.

The original image is preserved without recompression: dropped files retain their
exact bytes, dropped image data is stored as TIFF, and captured frames are stored at
native resolution as PNG. Position and zoom are separate metadata. Only audio export
renders the crop (up to 1600 pixels), using PNG for transparent rounded corners and JPEG for opaque square corners. **Artwork → Capture
Frame**, **Edit Crop…**, and **Remove Crop** are menu actions; the main window has
no capture/crop buttons or crop checkbox. Image files and image data can be dropped
onto the artwork area.

## Project bundles

Finder treats `.bootlegger` directories as documents. Use Show Package Contents to
inspect their contents:

```text
Concert.bootlegger/
  Project.json     # format version, album metadata, song IDs/titles/artists/ranges
  Video.mov        # imported video, retaining its original extension
  Artwork.png      # optional original artwork; extension follows its source format
```

The project is self-contained: the original video may be moved or removed after
import. Exported audio is never included in the project. Copying or saving large
videos requires sufficient disk space; saving is currently synchronous and may
pause the window while media is copied. Import copying runs off the main thread.

## Development checks

The existing shared Swift baseline is documented in `CODE_STYLE.md`. Install
SwiftLint separately if needed; swift-format ships with Xcode.

```sh
zsh swift-baseline.sh format
zsh swift-baseline.sh check
zsh scripts/test.sh
```

The native integration harness generates a six-second H.264 movie with audio,
exports overlapping ranges, checks durations and embedded metadata/artwork, and
round-trips a project after removing the original source. It also checks timestamp
parsing, invalid ranges, and independent document state/players. It does not modify
Apple Music. `zsh scripts/test.sh --keep-fixture` retains a generated demo project
under `.build/Fixtures` for inspecting the editor.

## Apple Music verification

The user performs this verification with a real concert:

1. Make two or three short ranges with recognizable starts and ends, including an
   overlap and a gap. Set an album title/artist, an artist override on one song,
   a date/year and genre, and capture a cover.
2. Export into a fresh folder. Listen to each file and compare its boundaries with
   the project; tiny AAC packet/decoder differences should be assessed by ear.
3. Drag the exported M4As into Apple Music. Check that they group as one album and
   that Get Info shows title, album, album artist, song artist, track number/total,
   genre/year, and cover art. Check the venue in Comments.
4. Save, close and reopen the project. Confirm metadata, artwork and ranges survive.
   Move the original video and reopen again to confirm the project copy plays.
5. Open a second project and confirm editing/seeking in one does not affect the other.

Native AVFoundation read-back has verified tags and trim durations in generated
exports. Apple Music's actual import, album grouping, date interpretation and cover
presentation still require the user's check. Codec support is whatever native
macOS frameworks can decode; unsupported or protected videos may fail.

## Current limits

Album artwork only; no individual song covers, fades or automatic song recognition.
Automatic saving/recovery and full-concert timeline zoom remain future work.
The app icon uses the supplied boot/record branding; its asset catalog includes all
standard macOS sizes. The original icon sheet is preserved as the branding reference. No downloads, accounts, cloud services, MP3 or FFmpeg.

MIT licensed; see `LICENSE`.

Audio-only sources use the same playback, marking, level prescan, project storage,
and export flow as video. Frame capture is disabled for them; artwork can be dropped
separately. The persisted `videoFilename` JSON key remains unchanged for compatibility
with earlier projects and can point to either audio or video.

The app declares its icon explicitly in Info.plist and assigns the bundled ICNS as
NSApplication's live icon at launch, refreshing the Dock tile. The About panel uses
the same resource. No Dock reset or global icon-cache deletion is required.

## Artwork search

Choose **Artwork → Search Artwork…** (Shift-Command-F). This reuses the DuckDuckGo
image-search workflow from the IIgs builder and MacroPad companion: edit the query,
choose Search, click a thumbnail to preview, drag to pan and use the zoom slider
or pinch. Choose **Use This Crop** to keep the selected square crop as editable
metadata, or **Use Full Image** to keep the image uncropped. The initial
query uses the album artist/title when available. A local-image chooser is available
in the search window as a fallback.

The downloaded original is kept unchanged and its image format is detected.
Selecting a new result resets the search preview's pan/zoom; applying it replaces
any previous cover crop with the chosen crop (or no crop for Use Full Image). Double-click the cover in the main window to adjust its
nondestructive crop. Search uses nonpersistent WebKit sessions and bounded image
downloads; it requires a working network connection and provider availability.

When importing a recording into an album with no title, Bootlegger suggests a title
from the original filename: underscores, dots and hyphens become spaces, repeated
separators collapse, and title capitalization preserves common acronyms and mixed-case
names. A blank Year field uses the last standalone 1900–2099 year in the filename.
Existing title/year values are preserved, including when replacing the recording.

Artwork editors support 0.1–20× zoom, including black padding when zoomed out. Corner radius defaults to 8 output pixels and can be adjusted; rounded corners are transparent in the exported PNG. Original artwork and editable crop settings remain in the project.

Click anywhere in a song row to select it, including its padding and controls. Enlarging the window gives additional vertical space to the track list after the player and metadata section reaches its content height.

### Export selection and strategies

**Export Album…** opens a preparation sheet before any files are written. All tracks
start selected; uncheck tracks or drag rows to change their export order. The total
shows the sum of selected track durations. These choices do not change the project.
The export button performs the selected strategy. Without a NetMD recorder it starts
with **Export to Files**, and **Write to MD** is absent from its menu. With a supported
NetMD recorder attached, **Write to MD** appears and becomes the initial default.
Connection changes update the available choices while preparation is open. The menu
also offers **Write to CD**, currently a placeholder. File export asks for a destination and
numbers the selected tracks in export order. MD uses the native NetMD helper described
below. CD currently shows a not-implemented alert.

### File export options

The **Options** gear immediately before the export button sets the format, AAC bitrate (128–320 kbps),
lossless/PCM bit depth (16 or 24 bit), sample rate (44.1 or 48 kHz), and filename
format. Popup changes are remembered automatically. Supported output is AAC or Apple Lossless in M4A, plus uncompressed WAV,
AIFF, and CAF. All output is stereo. M4A includes album tags and artwork; PCM
containers currently contain audio only. MP3 encoding is not provided by this app.

The filename field combines editable separators/text with draggable token pills:
Track #, Track Name, Artist, Album, Album Artist, and Year. Drag tokens from the
palette into the field or click to append; tokens within the field can be moved.
The default is `<track #>-<track name>` (for example `01-Opening Song.m4a`). Track
numbers follow the selected export order. The extension is added automatically.
A live preview shows the result; duplicate names are rejected before export.

Export options appear only in export preparation popups. There is no export Settings
or Preferences window and no saved default export strategy. MD options stay hidden
until a NetMD recorder is attached and MD is selected in the export button's menu.

### Writing directly to MiniDisc

Connect one supported NetMD recorder in standard MD mode and open export preparation.
MD becomes the default; choose the **Options** gear, insert a recordable disc, and choose
**Refresh**. The sheet shows
the recorder, existing tracks, available capacity in the selected mode, and whether
gapless SP is available. **Write to MD** prepares 44.1 kHz, 16-bit stereo PCM directly
from the source and transfers selected tracks in export order. Existing tracks are
preserved; appending does not change the existing disc title.

SP with the recorder’s encoder is the baseline. The MD **Options** popup also offers
software ATRAC encoding where supported: ATRAC3 for LP2/LP4, and ATRAC1 SP only on
recorders that explicitly support that upload path. On the MZ-RH1, SP uses recorder
encoding and LP2/LP4 use software encoding. Software LP4 remains experimental pending
playback/timing verification. Pre-encoding reduces USB payload, but total speed also
depends on encoding time and the recorder. LP modes trade quality for playing time;
software SP can sound different from the recorder's encoder. Hi-MD format writing is
not implemented. Mode, encoder and gapless settings are remembered automatically.

Available capacity and the 255-track limit are checked before preparing audio and
again in the native helper immediately before writing. Capacity reserves whole
SP-equivalent allocation clusters (176 × 512 / 44,100 seconds), plus one extra cluster
per recording for transfer/encoder padding, so borderline selections may be rejected
conservatively. Write-protected discs are rejected. **Erase / Format Disc…**
asks for explicit confirmation, deletes every track, and refreshes capacity. It does
not convert between standard MD and Hi-MD. Changed disc/device snapshots are rejected.

Gapless SP is used only on supported recorders with an empty disc. Selected ranges
are concatenated in export order, written as one recording, then split through TOC
editing. The new layout is checked for lost/overlapping audio groups before writing.
Recovery TOCs are retained in `~/Library/Application Support/Bootlegger/NetMDRecovery/`.
Other cases transfer tracks individually. **Stop After Track** requests a stop at a
safe boundary; during a gapless concert it finishes the continuous recording and
track markers. Keep the recorder connected until the operation completes. A failed
transfer can leave completed tracks on the disc; refresh before retrying.

The native helper and its dependencies are bundled; Homebrew and Node are not
required to run the app. For the first build from a new checkout, run:

```sh
NETMD_FETCH=1 zsh scripts/build-netmd.sh
```

This downloads checksum-verified dependency source archives into `.build/NetMD`,
then compiles locally with Xcode command-line tools and CMake. Xcode's NetMD build phase uses
that cache and signs/copies the helper. The helper is built for the current Mac's
architecture. Its source archives, build script, and license notices are bundled in
`Contents/Resources/NetMDSources`; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The single **Options** gear immediately before the export button shows settings for
the selected method. Choosing a method in the dropdown only selects it; it does not
start an export, open a settings popup, or trigger the CD placeholder alert. Use the
gear to review settings, then click the main export action when ready.

For NetMD staging only, the app normalizes padded/extensible macOS WAV files to
classic integer PCM RIFF before transfer. Audio sample bytes are copied unchanged;
normal file export and the original concert recording are unaffected. Software ATRAC
runs offline using bundled ATRACDEnc, with its source and dependency notices included.

On macOS, the NetMD adapter sends large encrypted packets through bounded 16 KiB
USB writes. This avoids the RH1 timeout/disconnection reproduced with 1 MiB host
requests, without changing the encoded audio. Failed operations retain backend
WARN/CRITICAL details and a diagnostic log path instead of reporting only a generic
error number. Normal device inspection does not reset the USB recorder.

## NetMD TX preview

The **NetMD TX** Xcode scheme builds a separate menubar app. Choose **Show MiniDisc**
from its optical-disc menu icon. The track table accepts Finder drops to copy
recordings to MD; supported tracks can be dragged into Finder as WAV or original
ATRAC files. Refresh and remembered transfer settings live in the unified toolbar.
See [NETMD_TX.md](NETMD_TX.md) for capabilities and remaining work.
