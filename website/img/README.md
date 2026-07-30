# Screenshots for clubcaddy site

Drop real app screenshots here. The site references them by these exact
filenames. Until a file exists, the slot shows a tasteful “Screenshot
pending” placeholder, so the layout never breaks - just replace the
placeholder by adding the file.

Capture on an iPhone (best quality - real GPS, real course data, real
device pixels). Portrait screenshots straight from the device are ideal;
they crop to the 9:19.5 frame automatically.

| File                  | What to show                                                                 | Priority |
|-----------------------|------------------------------------------------------------------------------|----------|
| `hero-game.png`       | The in-game aerial view on a hole - header pill (hole/par/tee/HC), the crosshair with To Green / Current Shot tags, and the bottom distance card (Mid Green + Bunker Front/Carry). The hero image - most important. | ★ must-have |
| `shot-green3d.png`    | The 3D green terrain view, showing slopes/tiers.                             | nice-to-have |
| `shot-scorecard.png`  | The scorecard with round history.                                            | nice-to-have |
| `shot-insights.png`   | Hole / round insights - fairways-hit, GIR, putting stats.                    | nice-to-have |

## Tips
- Take the in-game shot standing on a fairway so the yardages and the
  fairway-aware target look realistic; hole 1 (which has the sample
  fairway + bunker data) shows the Front/Carry bunker card.
- Hide any personal info before screenshotting (no member names/emails).
- PNG is fine; the site is static so file size isn’t critical, but keep
  each under ~1 MB for fast load.

## Alternative: capture from the simulator
If you’d rather not screenshot on your phone: run the app in the iOS
simulator, navigate to the screen you want, leave it front-most, and ask
me - I'll capture it with `xcrun simctl io booted screenshot img/<file>.png`
and it lands in the right place automatically.