# Greystones Caddy v1 Round Flow – QA Checklist

Production-readiness checklist for the core round flow. Use for regression testing before release.

See also:
- `v1-core-round-flow-release-readiness.md` – Release-readiness summary
- `v1-core-round-flow-test-log-template.md` – Template for recording test session findings
- `v1-core-round-flow-bug-triage.md` – Bug severity and triage guidance

## Canonical v1 Behavior (Reference)

- Round record created immediately on Start round
- Only one in-progress round at a time
- Closing app mid-round leaves round `in_progress` and resumable
- Explicit abandon marks round abandoned and keeps it in history
- Stroke play only (Stableford UI may appear for legacy rounds)
- Strokes per hole valid range 1–15
- Putts 0–10 (chip-ins = 0 putts)
- Penalties included in total strokes; no separate penalty field in v1
- Total score derived from hole_scores
- Complete round is explicit
- Missing scores trigger warning and override option
- History shows completed, abandoned, and in-progress rounds
- Only completed rounds contribute to stats
- v1 stats only: total score and total putts

---

## Test Scenarios

### 1. Round Start / Single Active Round

| Scenario | Steps | Expected |
|----------|-------|----------|
| Start new round (no active) | Home → Start new round → configure → Start Round | Round created, navigates to MainGameView, `activeRoundId` set |
| Attempt start when in-progress exists | With in-progress round → Start new round → Start Round | Alert "Round in progress" with Resume / Cancel |
| Resume from alert | Tap Resume in alert | Navigates to MainGameView for existing round |

### 2. Resume / Abandon Behavior

| Scenario | Steps | Expected |
|----------|-------|----------|
| Resume active round | Home → Resume active round (when banner shown) | MainGameView for active round |
| Resume from history | Home → tap in-progress round in list | MainGameView, `activeRoundId` set |
| Abandon round | During round → Tools → Abandon round → confirm "Abandon round" | Alert confirms; round marked abandoned; fullScreenCover shows RoundDetailView; Done returns to Home |
| Cancel abandon | Abandon round → Cancel | No change |
| Close app mid-round | Start round → force-quit app → reopen | Round still in_progress; Resume active round appears |

### 3. Shot Capture / Edit / Delete

| Scenario | Steps | Expected |
|----------|-------|----------|
| Log shot with club + GPS | MainGameView or LiveHoleView → log shot → confirm | Shot recorded; strokes/events update |
| Edit shot club/position | Tap pencil on shot → change club/position → Save | Shot updated; totals refresh |
| Delete shot | Tap trash on shot | Shot removed; totals refresh |

### 4. Score and Putts Entry Validation

| Scenario | Steps | Expected |
|----------|-------|----------|
| Enter valid strokes/putts | Scorecard or Office scorecard → set strokes 1–15, putts 0–10 | Saved; totals update |
| Invalid strokes | Set strokes &lt; 1 or &gt; 15 | Validation message "Strokes must be 1–15" |
| Invalid putts | Set putts &lt; 0 or &gt; 10 | Validation message "Putts must be 0–10" |
| Clear hole score | Swipe Clear on hole | Score removed; totals update |

### 5. Complete Round Flow

| Scenario | Steps | Expected |
|----------|-------|----------|
| Complete with all holes scored | RoundStatsView → Complete round | Completes without warning; navigates to RoundDetailView |
| Complete with missing holes | Some holes unscored → Complete round | Alert "Holes X, Y, Z have no scores. Complete anyway?" |
| Override missing scores | Alert → Complete anyway | Round completes; navigates to RoundDetailView |
| Cancel completion | Alert → Cancel | Stays on RoundStatsView; round remains in_progress |

### 6. Round History List / Detail

| Scenario | Steps | Expected |
|----------|-------|----------|
| History list states | Home → Round history | Date, course, total score, state (In progress / Completed / Abandoned) |
| Open round detail | Tap completed or abandoned round | RoundDetailView with hole list, total score, total putts |
| Totals from hole_scores | RoundDetailView | Total score and total putts match hole_scores |

### 7. Edit After Completion

| Scenario | Steps | Expected |
|----------|-------|----------|
| Edit completed round | RoundDetailView → Scorecard or Office scorecard → change score → back | Totals refresh on return |
| Edit Office scorecard | Change strokes/putts → back | RoundDetailView totals update |

### 8. Stats Eligibility

| Scenario | Steps | Expected |
|----------|-------|----------|
| Stats exclude in-progress | Stats Dashboard with in-progress round | In-progress round not in chart or aggregates |
| Stats exclude abandoned | Stats Dashboard with abandoned round | Abandoned round not in chart or aggregates |
| Stats include completed only | Complete rounds → Stats Dashboard | Only completed rounds in chart and aggregates |

---

## Edge Cases

- **No GPS**: Shot capture may use last known location or placeholder
- **Empty hole_scores**: Total score/putts show 0 or — until scores entered
- **Legacy rounds without completionState**: Treated as completed if `endedAt` set
- **Stableford rounds**: Stableford UI may show for rounds with `gameType == .stableford`; v1 focus is stroke play

---

## Regressions to Watch

- Abandon must persist (completionState = abandoned) and user must not be forced back into the round; confirm "Abandon round" performs the commit
- Totals not refreshing after Scorecard/Office scorecard edit
- In-progress round not resumable after app restart
- Duplicate in-progress rounds (should be prevented by RoundSetupView guard)
- Stats Dashboard including in-progress or abandoned rounds
- Complete round failing when hole_scores empty but shots exist (override should still work)

---

## Manual Test Items

- [ ] Full round: start → log shots on several holes → enter scores → complete
- [ ] Abandon mid-round → verify in history with "Abandoned" label
- [ ] Force-quit during round → reopen → verify "Resume active round" works
- [ ] Edit completed round scores → verify totals refresh
- [ ] Complete with missing holes → override → verify round completes
