# Transparent website previews

The original `home.png`, `remote.png` and `onboarding.png` are preserved.
The website uses `home-transparent.png`, `remote-transparent.png` and
`onboarding-transparent.png` (950 × 1656 RGBA PNG).

Mode: built-in image generation tool, reference-image editing, transparent
background enabled. These are presentation edits of app previews using
simulated TV state, not unmodified screen captures. Model-based editing may
slightly change raster detail; use original images for exact UI inspection.

Prompt template, applied separately with name = home, remote, onboarding:

> Use case: background-extraction. Edit target: attached {name} native macOS Sofa app screenshot. Make ONLY the pure white outer background surrounding the rounded gray app panel and its tiny top-center popover pointer fully transparent. Output a true RGBA transparent PNG cutout. Preserve the original screenshot panel contents exactly: every letter, number, icon, logo, button, layout position, gray fill and material, dimensions/aspect ratio and edge geometry unchanged. Keep the white pixels INSIDE the UI, especially app logos, labels and controls. Do not redesign, redraw, regenerate text, add shadows or add any content. Preserve the small top-center triangle and rounded panel corners. This is production screenshot background removal only, not a UI mockup. No checkerboard drawn into the file, no white matte or halo.
