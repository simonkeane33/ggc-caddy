# Greystones Caddy v1 Round Flow – Test Log Template

Reusable template for recording findings from broader manual/device testing. Copy this file or duplicate the tables for each test session.

---

## Test Session Info

| Field | Value |
|-------|-------|
| Device | _e.g. iPhone 17 Simulator, iPhone 15 Pro physical_ |
| iOS version | _e.g. 18.6_ |
| Build | _e.g. Debug, TestFlight build 42_ |
| Tester | |
| Date | |

---

## Release Test Matrix

Use this matrix to ensure coverage across key dimensions:

| Dimension | Options | Notes |
|-----------|---------|-------|
| **Environment** | Simulator / Physical device | Physical device for GPS, background behavior |
| **Install type** | Fresh install / Returning user | Returning user has existing rounds, preferences |
| **Round type** | New round / Resumed round | Resumed tests in-progress persistence |
| **Round outcome** | Completed / Abandoned | Both must appear correctly in history |
| **Stats verification** | Completed-round-only | Stats Dashboard excludes in-progress and abandoned |

**Suggested minimum coverage:** Fresh install + returning user; new round + resumed round; at least one complete and one abandon; stats check with mixed round states.

---

## Test Results

### Scenario 1: Round Start / Single Active Round

| Scenario | Expected | Actual | Pass/Fail | Severity if failed | Notes / Repro |
|----------|----------|--------|-----------|-------------------|---------------|
| Start new round (no active) | Round created, MainGameView | | | | |
| Attempt start when in-progress exists | Alert "Round in progress" | | | | |
| Resume from alert | MainGameView for existing round | | | | |

**Regression area:** Round creation, single active guard  
**Fix owner / follow-up:**

---

### Scenario 2: Resume / Abandon

| Scenario | Expected | Actual | Pass/Fail | Severity if failed | Notes / Repro |
|----------|----------|--------|-----------|-------------------|---------------|
| Resume active round (banner) | MainGameView | | | | |
| Resume from history list | MainGameView, activeRoundId set | | | | |
| Abandon round | Alert → abandoned → RoundDetailView | | | | |
| Cancel abandon | No change | | | | |
| Close app mid-round → reopen | Resume active round appears | | | | |

**Regression area:** Resume, abandon, persistence  
**Fix owner / follow-up:**

---

### Scenario 3: Shot Capture / Edit / Delete

| Scenario | Expected | Actual | Pass/Fail | Severity if failed | Notes / Repro |
|----------|----------|--------|-----------|-------------------|---------------|
| Log shot with club + GPS | Shot recorded, totals update | | | | |
| Edit shot club/position | Shot updated, totals refresh | | | | |
| Delete shot | Shot removed, totals refresh | | | | |

**Regression area:** Shot capture, edit, delete  
**Fix owner / follow-up:**

---

### Scenario 4: Score and Putts Entry

| Scenario | Expected | Actual | Pass/Fail | Severity if failed | Notes / Repro |
|----------|----------|--------|-----------|-------------------|---------------|
| Valid strokes/putts (1–15, 0–10) | Saved, totals update | | | | |
| Invalid strokes | "Strokes must be 1–15" | | | | |
| Invalid putts | "Putts must be 0–10" | | | | |
| Clear hole score | Score removed, totals update | | | | |

**Regression area:** Score validation, hole_scores  
**Fix owner / follow-up:**

---

### Scenario 5: Complete Round Flow

| Scenario | Expected | Actual | Pass/Fail | Severity if failed | Notes / Repro |
|----------|----------|--------|-----------|-------------------|---------------|
| Complete with all holes scored | Completes, RoundDetailView | | | | |
| Complete with missing holes | Alert lists unscored holes | | | | |
| Override missing scores | Completes | | | | |
| Cancel completion | Stays in_progress | | | | |

**Regression area:** Completion, missing-score override  
**Fix owner / follow-up:**

---

### Scenario 6: History List / Detail

| Scenario | Expected | Actual | Pass/Fail | Severity if failed | Notes / Repro |
|----------|----------|--------|-----------|-------------------|---------------|
| History list | Date, course, total score, state | | | | |
| Open round detail | Hole list, total score, total putts | | | | |
| Totals from hole_scores | Match hole_scores | | | | |

**Regression area:** History, round detail, totals  
**Fix owner / follow-up:**

---

### Scenario 7: Edit After Completion

| Scenario | Expected | Actual | Pass/Fail | Severity if failed | Notes / Repro |
|----------|----------|--------|-----------|-------------------|---------------|
| Edit completed round (Scorecard) | Totals refresh on return | | | | |
| Edit completed round (Office scorecard) | Totals refresh on return | | | | |

**Regression area:** Edit-after-completion, totals refresh  
**Fix owner / follow-up:**

---

### Scenario 8: Stats Eligibility

| Scenario | Expected | Actual | Pass/Fail | Severity if failed | Notes / Repro |
|----------|----------|--------|-----------|-------------------|---------------|
| Stats exclude in-progress | Not in chart/aggregates | | | | |
| Stats exclude abandoned | Not in chart/aggregates | | | | |
| Stats include completed only | Only completed in chart/aggregates | | | | |

**Regression area:** Stats eligibility  
**Fix owner / follow-up:**

---

## Session Summary

| Metric | Count |
|--------|-------|
| Passed | |
| Failed | |
| Blocked | |
| P0 issues | |
| P1 issues | |

**Overall:** Pass / Fail / Blocked

**Notes:**
