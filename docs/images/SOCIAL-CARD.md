# Website sharing card

Current asset: `sofa-social-v2.png`, 1200 × 630 PNG, with opaque painted background.
Used by Open Graph and X's `summary_large_image` metadata.

Reproduce with `swift scripts/render-social-card.swift "$PWD"` from the repository root.
The card is drawn with AppKit from the real native Icon Composer export and existing app preview screenshots (`icon.png`, `home-transparent.png`, `remote-transparent.png`). No generated raster artwork is used in v2.

Copy: “Sofa”, “for Mac”, “Your TV, from your Mac.”, “A little remote in your menu bar.”, “Free & open source · macOS 26+”.

Use a new filename when replacing the card so crawlers can fetch new bytes. Social platforms control their own caches; metadata or HTTP checks cannot prove X has refreshed its preview. Do not post to the user's account just to test the card.

`sofa-social-v1.png` is retained as a historical asset and is no longer referenced by the website.
