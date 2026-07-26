# Greystones Caddy v1 Core Round Flow – Release Readiness

Concise release-readiness package for the implemented and tested v1 core round flow.

---

## Purpose

This document captures the ship-readiness status of the v1 core round flow: what is in scope, what was validated, what is deferred, and what checks remain before broader testing or release.

---

## Confirmed v1 Scope

The following are implemented and aligned with the canonical flow:

- **Round creation on start** – Round record created immediately when user taps Start Round; `completionState = in_progress`, course stored
- **Shot logging with GPS and club** – Shots recorded with location and club; edit/delete supported
- **Strokes and putts per hole** – Entry via Scorecard and Office scorecard; `hole_scores` is canonical source
- **Score validation** – Strokes 1–15, putts 0–10; validation messages on invalid input
- **Explicit round completion** – "Complete round" from RoundStatsView; no auto-completion
- **Missing-score warning with override** – Alert lists unscored holes; "Complete anyway" / Cancel
- **Round states** – `in_progress`, `completed`, `abandoned`; only one in-progress round at a time
- **Round history list** – Date, course, total score, completion state; newest first; in-progress resumable
- **Round detail view** – Hole-by-hole scores, total score, total putts from `hole_scores`
- **v1 stats package** – Total score and total putts only
- **Stats eligibility** – Only completed rounds contribute to stats; in-progress and abandoned excluded

---

## Implemented Surfaces

| Surface | Role |
|---------|------|
| HomeView | Start round, resume active round, round history list |
| RoundSetupView | Configure tee/units, single active-round guard, create round |
| MainGameView | Map-based shot logging, tools (Complete/Abandon), scorecard access |
| LiveHoleView | Hole-focused shot logging, tools (Complete/Abandon), scorecard access |
| ScorecardView | Hole-by-hole strokes/putts entry (active or specific round) |
| OfficeScorecardView | Hole-by-hole strokes/putts entry for a round (edit after completion) |
| RoundStatsView | v1 stats (total score, total putts), completion flow, missing-score override |
| RoundDetailView | Round metadata, hole list, total score/putts, links to Scorecard/Office scorecard/Stats |
| StatsDashboardView | Aggregated stats (avg score to par, best round, putts) from completed rounds only |

---

## Validation Completed

Manual testing performed against `v1-round-flow-qa-checklist.md`:

| Area | Status |
|------|--------|
| Start round (no active) | ✓ Round created, navigates to MainGameView |
| Single active round guard | ✓ Alert when in-progress exists; Resume/Cancel |
| Resume round | ✓ From Home banner and from history list |
| Abandon round | ✓ Alert, round marked abandoned, navigates to detail |
| Shot log / edit / delete | ✓ Shots recorded; edit/delete update totals |
| Score and putts entry | ✓ Validation 1–15 strokes, 0–10 putts |
| Completion flow | ✓ All scored: completes; missing: warning with override |
| Missing-score override | ✓ "Complete anyway" completes; Cancel keeps in_progress |
| History list / detail | ✓ Date, course, total score, state labels |
| Edit-after-completion refresh | ✓ Scorecard/Office scorecard edits refresh totals on return |
| Stats eligibility | ✓ Only completed rounds in Stats Dashboard |

---

## Known Non-Blocking Risks

- **Legacy Stableford UI** – RoundSetupView Game picker and RoundDetailView/OfficeScorecardView may show Stableford sections for rounds with `gameType == .stableford`. Outside primary v1 path; no change for v1.
- **Multiple Complete/Abandon entry points** – MainGameView and LiveHoleView both expose Complete round and Abandon round. Behavior is consistent; no functional risk.
- **Deferred stat fields in schema** – `round_stats_cache` and related tables may still store GIR, fairways, scramble. Not used by v1; safe to leave for future cleanup.

---

## Out of Scope for v1

- Handicap
- Driving distance, GIR, fairways hit, strokes gained, club analytics
- Match play, Stableford, fourball as active v1 scope
- Bag model
- Penalty analytics
- Advanced stats dashboards beyond total score and total putts

---

## Release Test Matrix

Use this matrix to ensure coverage across key dimensions:

| Dimension | Options | Notes |
|-----------|---------|-------|
| **Environment** | Simulator / Physical device | Physical for GPS, background behavior |
| **Install type** | Fresh install / Returning user | Returning user has existing rounds |
| **Round type** | New round / Resumed round | Resumed tests in-progress persistence |
| **Round outcome** | Completed / Abandoned | Both must appear correctly in history |
| **Stats verification** | Completed-round-only | Dashboard excludes in-progress and abandoned |

**Suggested minimum:** Fresh + returning user; new + resumed round; one complete + one abandon; stats check with mixed states.

---

## Go/No-Go Checklist

Before broader testing or release candidate:

- [ ] Full round flow: start → log shots → enter scores → complete
- [ ] Abandon mid-round → verify "Abandoned" in history
- [ ] Force-quit during round → reopen → verify "Resume active round" works
- [ ] Edit completed round scores → verify totals refresh
- [ ] Complete with missing holes → override → verify round completes
- [ ] Stats Dashboard shows only completed rounds

---

## Recommended Next Steps

1. **Broader device testing** – Run QA checklist on additional devices/simulators
2. **Regression pass** – Re-run checklist after any UI copy or minor cleanup
3. **Backlog capture** – Log v1.1/deferred items (handicap, GIR, fairways, etc.) for future sprints
4. **Optional** – Quarantine or hide legacy Stableford/Game picker UI if desired for v1 clarity

---

## Related Docs

- `v1-round-flow-qa-checklist.md` – Test scenarios and expected outcomes
- `v1-core-round-flow-test-log-template.md` – Template for recording test session findings
- `v1-core-round-flow-bug-triage.md` – Severity rubric and triage guidance for round-flow issues
