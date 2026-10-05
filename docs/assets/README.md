# Steno icons

The app icon is the orange stenographer notebook selected from concept 2. The menu bar uses concept C, reduced to an outline, two top binding loops and one handwritten mark. It is a monochrome template: macOS supplies the foreground color for light, dark and selected states.

## Files

- `Steno/Assets.xcassets/AppIcon.appiconset/`: the ten macOS icon sizes, generated from the 1024 px master `icon_512x512@2x.png`.
- `Steno/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf`: vector template with an 18 pt intrinsic size.
- `docs/assets/menu-icon.svg`: editable SVG equivalent.
- `scripts/generate-menu-icon.swift`: regenerates the PDF and SVG; run from the repository root with `swift scripts/generate-menu-icon.swift`.

Recording and Processing retain the red dot and hourglass. The icons add no dependency or animation.

## App icon generation

Created with the built-in ImageGen tool, using the original three-concept board as a reference. The result was resized to the macOS asset-catalog dimensions with `sips`.

Prompt:

> Use case: precise-object-edit. The attached board is a reference containing three icon concepts. Create a SINGLE final macOS app icon by faithfully extracting and faithfully recreating ONLY the middle orange stenographer-notepad icon (concept 2). Preserve its exact appealing design: upright small thick cream paper notepad slightly in perspective, orange leather cover visible at left and beneath, exactly two chunky brushed silver top binding loops, same loose blue-black handwritten ink strokes, warm orange/apricot rounded-square background tile with soft subtle studio lighting, lovely tactile materials and rounded friendly proportions. Preserve the proportions, colors, position and visual personality of the middle concept as closely as possible. Output one square high-resolution icon, front and center, with the orange rounded-square tile occupying the full square canvas bounds and transparent pixels only outside its rounded corners. No surrounding board, no numbers, no captions, no glyphs, no other icons, no white margin around tile, no exterior drop shadow, no outer frame, no watermark. This is the final app icon image; not a presentation or mockup. Keep all notebook content comfortably inside the tile. Do not alter subject or add props.
