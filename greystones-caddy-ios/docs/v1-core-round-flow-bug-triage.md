# Greystones Caddy v1 Round Flow – Bug Triage

Simple severity rubric and triage guidance for round-flow issues during broader testing and release-candidate evaluation.

---

## Severity Levels

| Level | Definition | Examples |
|-------|------------|----------|
| **P0** | Cannot start, play, or complete a round; data loss | Round creation fails; app crash on complete; rounds disappear; resume broken |
| **P1** | Core round flow works but serious correctness issue | Wrong total score; completionState wrong; stats include in-progress/abandoned; scores don't persist |
| **P2** | Non-blocking UX or polish issue | Confusing copy; slow refresh; minor layout glitch; validation message unclear |
| **P3** | Cosmetic / cleanup only | Stale TODO; minor typo; deferred UI visible but not confusing |

---

## Triage Guidance

### Release-Critical (P0/P1)

Treat these as release-critical for v1:

- **Round creation** – Start round must create a round and navigate to play
- **Persistence** – Rounds must survive app close; in-progress must be resumable
- **Completion** – Explicit complete must work; missing-score override must work
- **Resume** – In-progress round must be resumable from Home
- **Abandon** – Explicit abandon must mark round abandoned and keep in history
- **Score correctness** – Total score and total putts must match `hole_scores`
- **Stats eligibility** – Only completed rounds in Stats Dashboard; in-progress and abandoned excluded

### Lower Priority (P2/P3)

- **Deferred stats** – GIR, fairways, scramble, driving distance; not in v1 scope
- **Handicap** – Out of v1 scope
- **Legacy non-v1 UI** – Stableford sections, Game picker; lower priority unless they confuse or break the active v1 path
- **Cosmetic** – Typos, minor layout; P3 unless they mislead the user

### When in Doubt

- If the user cannot complete a full round flow → P0
- If scores or totals are wrong → P1
- If the flow works but is confusing or ugly → P2
- If it's cleanup only → P3

---

## Quick Reference

| Area | Critical? | Typical severity if broken |
|------|-----------|----------------------------|
| Start round | Yes | P0 |
| Resume round | Yes | P0 |
| Abandon round | Yes | P1 |
| Complete round | Yes | P0 |
| Missing-score override | Yes | P1 |
| Score/putts entry | Yes | P1 |
| Totals refresh | Yes | P1 |
| Stats eligibility | Yes | P1 |
| History list/detail | Yes | P1 |
| Shot log/edit/delete | Yes | P1 |
| Legacy Stableford UI | No | P2/P3 |
| Handicap UI | No | P3 |
