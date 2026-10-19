# Website sharing card

Asset: `sofa-social-v1.png`, a 1774 × 887 (2:1) opaque PNG.
Used by both Open Graph and X's `summary_large_image` metadata.

Mode: built-in image generation, reference-based promotional composition.
Inputs: `icon.png`, `home-transparent.png`, `remote-transparent.png`.
The UI panels are illustrative app previews, not exact native screenshots.
The original screenshots and cutouts remain unchanged.

Use a new filename for future card artwork so crawlers can fetch new image
bytes. Page/card caches are controlled by each sharing platform; HTTP checks
with a Twitterbot user agent do not prove that X has refreshed its cache.
The X validator currently requires sign-in. Never post from the user's account
just to test a card without explicit posting authorization.

Generation prompt:

Use case: ads-marketing.
Asset type: production social sharing card for Sofa's website, especially X summary_large_image and Open Graph. Generate a wide 2:1 landscape PNG, ideally 1536 x 768 pixels, opaque background.
Input images: image 1 is the actual Sofa app icon, preserve its identity; image 2 is the Home UI reference; image 3 is the Remote UI reference. Use these as supporting product inserts, do not invent controls.
Design: premium minimal Apple-inspired software launch editorial. Solid deep forest green #101a18 background, pale mint #d6efaf and warm off-white type, subtle ambient green light behind two elegant glass app panels on the right. Crisp flat typography; large legible headline on the left. Beautiful generous negative space. Small app icon with Sofa name at top left. Both dashboard and circular remote visible on right with tasteful small rotation and overlap, fully contained. Keep the main copy and logo at least 7% from all edges to tolerate social cropping. NO large white rectangles around panels.
Text verbatim only: "Sofa" with small "for Mac"; large two-line headline "Your TV." then "Within reach."; below "Your TV remote, in your Mac’s menu bar."; lower-left "Free & open source". Tiny bottom-right "App previews".
Keep the brand icon recognizable and panel proportions/UI faithful to references. No extra text, no download button, no unsupported compatibility, notarization, approval or availability claims, no URL, no watermark. Strong layout readable at a small mobile share-card size, restrained and polished.
