# Mobile check

Before the pull request:

1. Open the page at 360px wide and at 390px wide. Scroll from top to bottom.
2. Fix sideways scrolling, clipped text, overlapping sections, images wider than the screen, and buttons shorter than 44px.
3. Run `node mobile-check.mjs` until it prints PASS.

Result:
- Script: PASS
- Look at 360px and 390px: PASS
- Fixed: grouped job photos into full-bleed grid with `margin-inline: calc(50% - 50vw)` on `.job`; added `hero-actions` flex wrap for dual Call/WhatsApp buttons; ensured footer has 5.5rem bottom padding so fixed WhatsApp button clears contact text; added `loading="lazy"` on gallery images.
