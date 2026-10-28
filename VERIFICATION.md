# First implementation verification — 2026-10-28

## Automated native checks

`zsh scripts/test.sh` generates a disposable H.264 movie with a six-second audio
track and tests the same exporter and document classes used by the app:

- Timestamp parsing, millisecond carry, invalid/nonfinite/overflow input.
- Unicode export filename byte limits.
- Invalid ranges rejected; independent overlapping ranges accepted.
- Exports of 0.5–2.25 and 1.5–4.75 seconds read back as 1.75 and 3.25 seconds.
- Output contains AAC audio and no video.
- Song title, album, album artist, per-song artist override, track number/total,
  and JPEG artwork read back from the exported M4As. Genre, date and venue comment
  also appear in the native metadata read-back.
- Project metadata, media and artwork survive a save/reopen round trip after the
  original media is deleted. Bundled media bytes match the original source.
- Distinct documents have independent metadata and AVPlayer instances.
- Metadata edits can be undone and redone.
- Cancelled export leaves no partial album directory.
- Exports inside a `.bootlegger` bundle are rejected.
- Invalid media paths, missing media and unknown project versions produce errors.

`zsh swift-baseline.sh check` passes strict swift-format and SwiftLint checks.
Both Debug and optimized Release apps build with Xcode 27.1. The Release app
was launched and successfully opened the saved demo project. Xcode emits its standard notice that App
Intents metadata extraction was skipped because the app does not use App Intents.

## Checks through the running macOS app

Using only a generated test video and disposable projects:

- Launched the app, opened a project bundle and created an additional project window.
- Edited album metadata, saved, quit/relaunched and reopened the saved project.
- Dragged a song start handle; only that song's start changed.
- Entered a precise timestamp and used Up to nudge it by 0.1 second.
- Captured a video frame as album artwork.
- Deleted a song and restored it with Command-Z.
- Previewed a song and observed playback stop at its 2.25-second end boundary.
- Imported video through the native file picker into a new project, added a song,
  entered metadata, saved a new bundle and exported an M4A into a separate folder.
- Started playback in the newly imported project.

## Still requires user verification

Apple Music import/grouping and presentation of metadata/artwork, listening to real
concert cuts, and performance with full-length videos. See README.md for steps.
Automated checks use generated media; they do not establish compatibility with every
source codec, damaged file, or protected video.

## Video drop and replacement update — 2026-10-28

- Registered movie/video document types for Dock/Open With delivery and routed video
  URLs into the current project (or a new one when needed).
- Added window-wide URL drops and explicit AVPlayerView drop handling so native
  player drops update the document, rather than only changing the visible player.
- Added a shared replacement confirmation for drops, Dock delivery and the file picker.
- Native integration checks pass for initial import, cancelling replacement,
  confirmed replacement retaining metadata/ranges, same-extension dirty tracking,
  and an unreadable replacement preserving the previous media.
- The Debug app builds and strict format/lint checks pass.
- In a disposable project, the running app showed only Bootlegger's controls and
  displayed the replacement confirmation on delivery through macOS's file-opening
  route. Finder-to-window and Finder-to-Dock pointer drags still need user verification.

## Concert editing update — 2026-10-28

- Added document-local S/E marking, Space play/pause, Left/Right ten-second seeks,
  and Shift-Left/Right one-second seeks. Plain keys are ignored during text editing;
  Return commits a field and releases its focus through the editor's submit handler.
- Native tests use an invisible window to check arrow transport, modified menu keys,
  text-editor exclusion and transport resuming after field focus is released.
- Tests verify E creates/selects the next song only after the last listed song and
  before source end, with independent existing ranges retained.
- The editor displays one selected-song timeline, plus measured multichannel audio
  amplitude around the cursor. The display spans ±5 seconds down to ±0.1 second.
- Tools → Prescan Audio Levels fills the whole-concert in-memory cache. Tests check
  whole-source coverage, seeking reuse, save relocation, cancellation and reset.
- Artwork conversion tests cover original aspect ratio, center square cropping,
  cropping existing artwork and importing an image file into project artwork.
- File menu import/export actions use the same document operations as the toolbar.

The integration suite uses generated video and audio. Real-concert waveform
responsiveness, Finder/other-app image dragging and Return focus behavior in the
visible SwiftUI editor remain useful manual checks in Xcode.

## Nondestructive crop editor — 2026-10-28

This replaces the initial center-crop checkbox and buttons. The main window has no
capture/crop buttons or crop checkbox. Double-clicking artwork opens a square crop
sheet with panning, zoom slider/pinch, Reset, Remove Crop, Cancel and Apply. Capture
Frame and crop commands are in the Artwork menu.

Original image bytes and optional normalized crop metadata are saved separately.
Image-file drops preserve exact source bytes, image-data drops use lossless TIFF,
and native-resolution video frames use PNG. Previewing/applying a crop does not
rewrite the original. New artwork clears the crop. Audio export renders the crop
and encodes PNG for transparent corners or JPEG for opaque square corners.

Native tests pass for unchanged original bytes during preview/crop, exact-byte file
import and crop reset, fractional pan/zoom exporting an exact square, original plus
crop surviving save/reopen, and the selected crop being embedded in M4A artwork.
The existing project/export/editor test suite also passes, as do strict format/lint
checks and the Debug app build. Older projects without crop metadata remain readable.

The desktop inspection service stalled during the isolated visual check. The main
window's removed controls/menu were observed; pan/pinch/Apply/Cancel behavior in the
visible sheet remains a manual check in Xcode. Native crop rendering, persistence,
reset and export were verified by the integration suite.

## Live icon and audio recordings — 2026-10-28

The previous icon work produced AppIcon.icns and icon keys in the compiled bundle,
but did not explicitly assign NSApplication's live icon in this manually bootstrapped
AppKit app. Startup now loads that resource, assigns applicationIconImage and redraws
the Dock tile. Source Info.plist also declares CFBundleIconFile/CFBundleIconName.
Development build number is 2 so the About box identifies this build.

Import Recording accepts public.audio as well as movie/video types in the picker,
window drop, player drop and Dock registration. Audio-only sources use native playback,
marking, prescan and export; frame capture is disabled and a clear audio-only placeholder
is shown. Existing projects retain their original JSON videoFilename key for compatibility.
Native tests cover WAV import, audio duration/marking, frame-capture menu exclusion,
trimmed M4A output, measured prescan levels and bundled audio save/reopen after removing
the original source. Common MP3/M4A/WAV/AIFF/FLAC extension routing is checked as well.

## Artwork search integration — 2026-10-28

Adapted the local MacroPad IconPicker/IconSearchPage workflow, also used by the IIgs
builder, into Artwork → Search Artwork. The native search window provides DuckDuckGo
results, image preview, local selection and Use Image. It preserves original bytes
instead of baking in a crop. Search/download requests are cancelled when the window
closes, stale selections are discarded, and remote images have byte/pixel limits.
Native tests cover accepted image data, original-byte preservation, crop reset,
detected filename format, rejection without replacing existing artwork, and the
30 MB selection limit. Live provider results and visible WebKit interaction require
a manual network-enabled check; the automated suite does not contact search sites.

## Search zoom and track deletion correction — 2026-10-28

Track rows previously used array-index-backed bindings. Those bindings could outlive
an array slot during deletion/reordering, and the timeline retained an indexed binding
to the selected song. Rows now iterate value snapshots, bind by UUID on every access,
and ignore late writes to deleted songs. Timeline/audio-level drawing uses song values.
Selection repair runs after project storage changes, outside the publisher's willSet
notification. Deleting the selected track chooses a surviving neighbor, or clears the
selection for an empty list.

Regression tests pass for first/middle/last/only-track deletion, repeated deletion,
late field commits, bindings after reorder, undo/redo restoring the final song, and
SwiftUI list/timeline/audio graph reconciliation in an invisible hosting window.

The artwork search now includes a square pan/zoom preview, visible 0.1–20× slider,
pinch zoom, Use This Crop and Use Full Image. Applying a crop preserves original data
and stores normalized crop metadata. New results reset the preview. Native tests check
search preview pan/zoom, reset, and transfer of original data plus crop into the project.

## Editing focus, range ordering and filename metadata — 2026-10-28

Main-window string fields now use native commit-aware text fields. The document window
handles Return/keypad Enter/Escape before transport filtering, explicitly ends editing
and becomes first responder. Clicks outside editable fields release focus; hit-testing
uses superview coordinates so flipped SwiftUI/AppKit containers work correctly.
Unselected song rows show plain text instead of active editors.

All row/timestamp/timeline bindings and S/E mutations share identity-based range
validation. Reversed, equal, negative/nonfinite and out-of-source boundaries are rejected;
valid existing ranges and independent overlaps are retained. Timestamp fields display
the accepted stored value after rejection. EOF cannot create a zero-length song.
Older invalid saved ranges are reported on load and can be repaired without blocking
metadata edits.

Empty album title/year fields are seeded only after successful import. Filename title
cleanup normalizes separators, preserves dotted acronyms/mixed-case names, and applies
title casing. The last standalone year from 1900–2099 seeds a blank Year field. Existing
user metadata is never overwritten. Tests cover these defaults, replacement preservation,
Return/Escape release, outside clicks with flipped coordinates, and range rejection.

## Row selection, artwork padding and window sizing

Native regression checks cover row padding and control hit regions, text-focus handoff, hidden/deleted row guards, zoom-out black padding, transparent PNG corners, crop orientation, radius defaults and persistence. The upper player/metadata section is capped at metadata content height; surplus window height goes to the track list. Visible resizing and crop interaction remain manual Xcode checks.

## Export preparation and strategy preferences

Export-plan regression tests cover all-selected defaults, summed durations (including
overlap), deselection, reordered export snapshots, preservation of the saved project,
empty totals, and routing the export command to preparation without writing files.
The native preparation sheet uses list drag reordering and a split menu action;
Settings stores the default strategy in UserDefaults. MD/CD actions show placeholders.
Manual UI checks: drag selected and deselected rows, cancel the sheet/destination
panel, change Settings and reopen export, invoke each strategy, and verify exported
track numbers/order in Apple Music. No hardware writing is implemented.

## File encoding options and filename tokens

Native tests export and reopen AAC, ALAC, WAV, AIFF, and CAF, checking codec,
48 kHz sample rate, 24-bit PCM, trimmed duration, and M4A title metadata. Existing
AAC export tests also verify album tags, track numbers and binary artwork. Tests
cover preference defaults, filename expansion and sanitization, collision rejection,
and native token-field clipboard parsing/pill styles. Build and strict style checks
pass. Visible token insertion, dragging/reordering, editing literal separators, and
Settings-to-export overrides remain manual UI checks. WAV/AIFF/CAF tag writing is
not implemented and is stated in the UI.
