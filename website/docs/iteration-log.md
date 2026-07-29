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

## 2026-07-29 - GSPro section, pricing layout, copy updates & new Vercel project

### What was done
- Added dedicated **GSPro simulator build** spotlight section with `gspro-sim.jpg` and link to https://gsprogolf.com/.
- Added club recommendation to the feature grid.
- Made pricing tier cards equal height using `align-items: stretch` and `height: 100%`.
- Centered the annual/monthly billing toggle above the pricing cards.
- Centered the hero phone stack on mobile.
- Updated copy:
  - Tagline: "Your club. Your course. Your caddy."
  - "Free for your members" instead of "Free for members".
  - Removed dog-fooding comment and all em-dashes per house style rule.
  - Removed optional LiDAR wording from GSPro section (LiDAR is required for the sim build).
  - Softened gallery headline so it does not imply every screen is shown.
  - Removed Greystones external link but kept the case-study section.
  - Clarified browser-based explorer as a 3D photorealistic WebGL viewer using the same build as the GSPro sim.

### Deployment / project changes
- Moved from the old `simon-keanes-projects/website` project to a new clean project: **ClubCaddy** (`simon-keanes-projects/club-caddy`).
- New project URL: https://club-caddy.vercel.app.
- Root directory in Vercel is now set to `ggc-caddy/website`.
- Switched to Git-based branch workflow:
  - `sandbox` for development previews.
  - `main` for production, promoted manually in the Vercel UI.
- Removed deprecated `"public": true` from `vercel.json` which was blocking new project imports.
- Added `.vercel` and `.env*` to `.gitignore` to keep the repo clean.
- Removed accidental `ggc-caddy/website/website/` nested directory and old `.vercel` metadata.

### Why the workflow changed
- Direct CLI deploys (`vercel --prod`) created mismatched production aliases and caused 404s.
- A `sandbox` branch lets us iterate without touching production, and manual promotion gives control over when `main` goes live.

### Technical decisions
- Device-stack layout kept straight (not fanned) with side-visible rear images and a soft shadow on the foreground phone.
- Hero phone frame border-radius reduced by 50% for a subtler mask.
- Gallery images use consistent rounding on all corners.

### Open questions / possible next iterations
- Should the GSPro section have a separate inquiry form or direct email CTA?
- Add a short demo video for the GSPro sim or the 3D WebGL explorer?
- Contact/demo booking form instead of mailto links?

---

## How to update this log

After each round of changes or feedback, add a dated section with:
- What changed
- Why it changed (feedback / decision)
- Assets affected
- Open questions

Keep it short and factual - future-you will thank present-you.
