# Bootlegger

A small native macOS utility for turning a local concert recording into individually
trimmed, tagged AAC/M4A songs for Apple Music. SwiftUI provides the editor; AppKit
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
   fresh album directory with numbered M4A songs. Existing exports are never overwritten.
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
