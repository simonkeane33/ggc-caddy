# ClubCaddy Website - Iteration Log

A running record of changes, decisions and feedback so future iterations don’t lose context.

---

## 2026-07-28 - Initial build & first deploy

### What was done
- Created static marketing site in `ggc-caddy/website`.
- Built single-page layout: hero, proof strip, pitch, features, how it works, included band, case study, screenshot gallery, pricing, premium, FAQ, CTA, footer.
- Added responsive nav with mobile hamburger menu.
- Added annual/monthly pricing toggle.
- Created device-stack hero: branded home screen foreground + two aerial screenshots behind.
- Added 3-image screenshot gallery.
- Compressed and resized screenshots from ~20 MB total to ~7.6 MB.
- Deployed to Vercel via CLI (`simon-keanes-projects/website`).
- Added `vercel.json` for static deployment.
- Added this documentation.

### Assets used
| File | Source | Where it appears |
|---|---|---|
| `hero-home.png` | `IMG_0016.PNG` (Greystones home screen) | Hero foreground |
| `shot-course.png` | `IMG_0018.PNG` (in-game aerial full hole) | Hero background left, gallery |
| `shot-approach.png` | `IMG_0019.PNG` (close-up approach to green) | Hero background right, gallery |
| `shot-green3d.png` | `IMG_0020.PNG` (3D green terrain) | Gallery |

### Technical decisions
- No build tool; pure static HTML/CSS/JS.
- Vercel deploys only the `ggc-caddy/website` subdirectory.
- Phone frames are CSS masks (`border-radius` + `overflow: hidden`) over real PNG screenshots.
- Native screenshot aspect ratio preserved by letting images render naturally rather than forcing `aspect-ratio` + `object-fit`.
- Original `IMG_*.PNG` files ignored in `.gitignore` to keep the repo lean.

### Feedback / fixes applied same day
- **Widows in pitch heading/paragraph:** fixed by adjusting the paragraph text and adding `text-wrap: balance` to `.display` headings.

### Open questions / possible next iterations
- Should the hero phone frame be larger on desktop?
- Do we want a contact form instead of a mailto link?
- Should we add a short demo video or GSPro preview?
- Any club-specific landing pages needed?

---

## How to update this log

After each round of changes or feedback, add a dated section with:
- What changed
- Why it changed (feedback / decision)
- Assets affected
- Open questions

Keep it short and factual - future-you will thank present-you.
