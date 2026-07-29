# ClubCaddy Marketing Website

Static marketing site for ClubCaddy - the club-branded GPS course app built for golf clubs.

**Live URL:** https://club-caddy.vercel.app  
**Vercel project:** https://vercel.com/simon-keanes-projects/club-caddy  
**Project root:** `ggc-caddy/website`  
**Framework:** Static HTML / CSS / JavaScript (no build step)

---

## Purpose

This site is for sharing with clubs, committees and prospective customers. It explains what ClubCaddy is, what members get, how the mapping/branding process works, the Bronze/Silver/Gold pricing tiers, and the premium GSPro simulator build offering.

The design is intentionally simple so it can iterate quickly based on feedback.

---

## Branches & deployment workflow

- **`sandbox`** - development branch. Push work here first to get a preview deployment.
- **`main`** - production branch. Promote to production manually in the Vercel UI when ready.

Do not run `vercel --prod` from the CLI. Manual promotion via the Vercel dashboard keeps the production alias stable and avoids the 404 alias issues caused by direct CLI deploys.

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

The site is deployed via Vercel's Git integration, not the CLI.

1. Push changes to the `sandbox` branch.
2. Vercel builds a preview deployment automatically.
3. When you are ready to go live, merge/promote `sandbox` into `main` via the Vercel dashboard or GitHub.

Because the repo root (`ggc-caddy`) contains the iOS app and other folders, the Vercel project is configured to deploy **only** the `ggc-caddy/website` directory. If importing through the Vercel UI, set the root directory to `ggc-caddy/website` and the framework preset to **Other** (static).

### `vercel.json`

```json
{
  "trailingSlash": false
}
```

The deprecated `"public": true` property has been removed. If you see `Invalid request: should NOT have additional property public`, that means the branch being imported still has the old config.

---

## Image Assets

Screenshots are stored in `img/` and should be kept under ~3 MB each for fast loading. The originals (e.g. `IMG_0016.PNG`) are ignored via `.gitignore` at the repo root to avoid committing multi-megabyte source files.

| Asset | Use | Priority |
|---|---|---|
| `hero-home.png` | Hero foreground (home / branded screen) | Required |
| `shot-course.png` | Hero background left + gallery | Required |
| `shot-approach.png` | Hero background right + gallery | Required |
| `shot-green3d.png` | Gallery (3D terrain) | Required |
| `gspro-sim.jpg` | GSPro simulator build spotlight | Required |

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
Push to `sandbox` to get a preview. Promote to `main` via the Vercel dashboard for production.

Do not use `vercel --prod` from the CLI.

---

## Notes for Future Iterations

- The site is currently light on interactivity by design. Future versions may add a contact form, demo booking calendar, or live competition-tracking preview.
- Premium section is descriptive only; pricing is POA.
- Branding copy is currently generic/ClubCaddy - can be customised per-club if we ever build white-label landing pages.
