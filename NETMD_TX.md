# NetMD TX

Select the **NetMD TX** scheme in `Bootlegger.xcodeproj`. This separate
`nl.theredhead.NetMDTX` app stays in the menu bar without a Dock icon. Choose
**Show MiniDisc** from the optical-disc menu to reopen its window.

## Track window

The unified toolbar holds Rename Album, Refresh and Settings. The window title combines the
recorder name and disc title; its content is a track table with number, title,
recording format and duration. Transfer progress appears in a modal sheet during operations, with overall
percentage, filename and “Working on x of y.” The table and toolbar remain disabled
until the complete batch finishes.
There are no playback controls. Double-click a track title to edit it;
Return or leaving the field saves, and Escape cancels. Rename Album opens a title
sheet. Renames recheck disc identity/write protection, preserve existing group
metadata, enforce title storage limits, and refresh titles from the recorder.

Drop audio/video files from Finder into the table to copy them as separate MD
tracks using the remembered recording settings. TX checks the entire pending
batch for capacity and capability before writing. Pending copies appear in the
table; successfully copied items leave the queue. Failures retain unfinished
items and offer retry/discard. Stopping finishes the active recording safely.

Drag one or more supported recorded tracks from the table into Finder. Native
file promises defer extraction until a drop occurs, and device reads run in
sequence. Settings chooses decoded WAV (default) or original ATRAC1 AEA. Each
promise captures its disc identity, track index and output format; a stale disc
is rejected and existing destination files are never replaced. Temporary ATRAC
and decoded files are removed after delivery. Cancelling a drag before drop
performs no extraction.

Writable discs expose drag handles. Drag selected tracks between rows to save a
new order on the MD, retaining the selected tracks' relative order. Reordering
validates the captured disc identity and the complete permutation before any move,
then reads back the actual order. If a move fails partway through, TX refreshes the
actual state rather than assuming nothing changed.

Write-protected discs hide drag handles and Rename Album, and reject incoming
Finder drops and local reorder drops. Supported extraction remains available.

## Current capabilities

- Native digital extraction: Sony MZ-RH1, SP mono/stereo recordings.
- Offline ATRAC1 decoding through bundled ATRACDEnc; WAV output works with macOS.
- Device writes reuse Bootlegger's recording modes, encoders and capacity checks.
- Unsupported models/formats have drag-out disabled; no factory-mode extraction.
- The helper's process lock prevents simultaneous USB operations across apps.

Hardware validation read a 187.06-second SP track back from the RH1, decoded a
non-silent PCM signal, and confirmed an unchanged TOC. The user confirmed playback
worked before requesting removal of the playback UI. No new hardware writes were
used for the Finder workflow changes; Finder interaction is manually verified.

## Remaining work

A persistent device broker and disc-insertion events while the same recorder stays
attached; LP decoding/extraction support; additional supported recorder mechanisms;
disc management UI; richer whole-batch progress. Attachment monitoring enumerates
USB without repeatedly opening/resetting recorders. Use Refresh after a disc swap.
