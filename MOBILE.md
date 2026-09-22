# Mobile check

**Status: PASS**

Checked at 360px and 390px widths.

## Fixes applied
- Increased footer bottom padding from 5.5rem to 7rem so the fixed WhatsApp button does not cover the last line of footer text when scrolled to the bottom.
- Full-bleed gallery uses `100vw` with `overflow-x: clip` on html — no sideways scroll.
- Hero and contact Call/WhatsApp buttons use `min-height: 44px` with flex-wrap on `.hero-actions`.
- Brand name uses smaller font on narrow screens to avoid header overflow.
- Workshop stats stack to single column below 520px.

## Script
`node mobile-check.mjs` — PASS
