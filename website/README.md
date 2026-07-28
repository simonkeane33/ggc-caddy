# ClubCaddy Marketing Website

Static marketing site for ClubCaddy - the club-branded GPS course app built for golf clubs.

**Live URL:** https://website-rho-two-29.vercel.app  
**Project root:** `ggc-caddy/website`  
**Framework:** Static HTML / CSS / JavaScript (no build step)

---

## Purpose

This site is for sharing with clubs, committees and prospective customers. It explains what ClubCaddy is, what members get, how the mapping/branding process works, and the Bronze/Silver/Gold pricing tiers.

The design is intentionally simple so it can iterate quickly based on feedback.

---

## Structure

```
website/
├── index.html          # Single-page marketing site
├── styles.css          # All styles, responsive breakpoints
├── script.js           # Mobile nav, billing toggle, current year
├── vercel.json         # Static site config for Vercel
├── img/
│   ├── hero-home.png       # Hero foreground: branded home screen
│   ├── shot-course.png     # Hero background left: in-game aerial
│   ├── shot-approach.png   # Hero background right: approach to green
│   └── shot-green3d.png    # Gallery: 3D green terrain
└── README.md           # This file
```

---

## Key Design Decisions

- **Single page, section scroll.** All content lives in `index.html`. Navigation links anchor to sections (`#features`, `#pricing`, etc.).
- **Device-stack hero.** The hero shows three iPhone screenshots: a branded home screen in front, with two in-game aerial shots behind it to imply depth and product breadth.
- **Phone frames are CSS masks, not images.** Screenshots are real PNGs at their native aspect ratio; the rounded phone frame is applied via `border-radius` and `overflow: hidden`.
- **Screenshot aspect ratio:** 1170 × 2532 (iPhone screenshot native). Containers do not force aspect ratio - images render at their natural size and the parent clips them.
- **Gallery section:** Three screenshots showing aerial view, approach view and 3D green terrain.
- **Pricing toggle:** Annual/monthly toggle in the pricing section. Prices are hardcoded in HTML and toggled via `data-annual` / `data-monthly` attributes in `script.js`.
- **Static deployment on Vercel.** No build step. Root directory is `ggc-caddy/website`.

---

## Deployment

Deployed via Vercel CLI from this directory:

```bash
cd /Users/simonkeane/ggc-caddy/website
vercel --prod
```

Because the repo root (`ggc-caddy`) contains the iOS app and other folders, the Vercel project is configured to deploy **only** the `ggc-caddy/website` directory. If importing through the Vercel UI, set the root directory to `ggc-caddy/website` and the framework preset to **Other** (static).

---

## Image Assets

Screenshots are stored in `img/` and should be kept under ~3 MB each for fast loading. The originals (e.g. `IMG_0016.PNG`) are ignored via `.gitignore` at the repo root to avoid committing multi-megabyte source files.

| Asset | Use | Priority |
|---|---|---|
| `hero-home.png` | Hero foreground (home / branded screen) | Required |
| `shot-course.png` | Hero background left + gallery | Required |
| `shot-approach.png` | Hero background right + gallery | Required |
| `shot-green3d.png` | Gallery (3D terrain) | Required |

When replacing screenshots, keep filenames identical so the HTML/CSS references stay valid. Recommended size: ~936 × 2025 (80% of native) is sufficient for web while keeping files small.

---

## Iteration Notes

See [`docs/iteration-log.md`](docs/iteration-log.md) for a running history of changes, feedback and open questions.

---

## Common Tasks

### Update a screenshot
Replace the relevant file in `img/`. Keep the filename the same. If the file is missing, the page shows a "Screenshot pending" placeholder.

### Change pricing
Edit the `data-annual` and `data-monthly` attributes in the pricing section of `index.html`.

### Redeploy
```bash
vercel --prod --cwd /Users/simonkeane/ggc-caddy/website
```

---

## Notes for Future Iterations

- The site is currently light on interactivity by design. Future versions may add a contact form, demo booking calendar, or live competition-tracking preview.
- Premium section is descriptive only; pricing is POA.
- Branding copy is currently generic/ClubCaddy - can be customised per-club if we ever build white-label landing pages.
