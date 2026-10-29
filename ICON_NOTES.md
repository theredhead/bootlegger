# App icon

The color boot/record icon was isolated from `bootlegger icons.png` using the built-in image_gen tool (imagegen skill), then packaged with macOS `sips` into the standard 16–1024 pixel AppIcon variants.

Asset path: `Sources/Bootlegger/Resources/Assets.xcassets/AppIcon.appiconset`.

## Extraction prompt

Use case: background-extraction. Asset type: native macOS app icon master, square 1024x1024 PNG with genuine transparent surroundings. Edit target: the supplied icon sheet. Isolate ONLY the large full-color brown leather cowboy boot / black vinyl record / cream waveform and trim-marker icon in the upper-left of the sheet. Keep its original composition, warm leather textures, colors, rounded square tan background, and all design details as faithfully as possible. Remove the black sheet backdrop, monochrome right-hand icon, and all small icon samples. Deliver just that one large color rounded-square icon centered on a transparent square canvas, with approximately 8% transparent margin around the icon. No new design, no text, no extra shadow or decorative elements. Preserve rounded corners with transparent pixels outside the icon.

## Cleanup prompt

Use case: background-extraction. Edit target: this single boot/record macOS icon. Preserve the entire icon design, leather texture, colors, waveform, record and rounded tan tile exactly. Clean only the transparent surroundings: remove every stray colored speck and halo outside the rounded-square tile, especially the red/yellow pixels above its top edge. All padding outside the tile must be fully transparent with zero alpha. Keep a centered square canvas and clean approximately 8% transparent margins. No added elements, no redesign.

## NetMD TX icon

Generated with the built-in image_gen tool from the user's clear MiniDisc cartridge
reference. Master: `Sources/NetMDTX/Resources/NetMDTXIcon.png` (transparent PNG).
The dedicated `Sources/NetMDTX/Resources/Assets.xcassets/AppIcon.appiconset` contains
16–1024 pixel macOS variants made with `sips`. Only the NetMD TX target consumes
this catalog; Bootlegger's icon is unchanged.

### Generation prompt

Use case: stylized-concept. Asset: a single production macOS application icon for NetMD TX, square 1024x1024 master with genuine transparent surroundings. Reference image is subject reference, not a photograph to preserve: the clear MiniDisc cartridge with visible iridescent circular disc, central silver spindle and rectangular silver sliding shutter at the right. Create a polished stylized dimensional illustration, front facing, centered, clean strong silhouette, rounded square clear smoked-silver cartridge with subtly beveled edges and a few simplified molded details. The beautiful optical disc has restrained cyan, gold, violet rainbow reflections against dark reflective graphite, bright machined silver circular hub, and a distinct brushed silver right-hand shutter. The cartridge itself is the app icon shape: no extra background tile. Approximately 8 percent transparent margin, subtle close shadow only, beautiful clarity in light and dark mode, bold simplified details legible at small sizes. Reference the cartridge's distinctive geometry faithfully while simplifying it into a premium macOS app icon. Only one icon, not a sheet or mockup. No Sony logo, no brand lettering, no numbers, no text, no arrows, no extra objects.
