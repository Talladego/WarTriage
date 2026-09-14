# WarTriage CODE_QUALITY 3.04

**Date:** 2026-09-14 (Europe/Stockholm)  
**Version:** 3.04 (`WarTriage.mod` / `VERSION = 3.04`)  
**HEAD:** `5e4cb5a67c25c234b1a388ac070925a02ab36577`  
**Prior pass:** 3.00 on 2026-09-13 (issues #2–#11)

## Verdict

3.04 lands the intended structural fixes for #3–#11, but the cooldown replacement uses the wrong API semantics. **Rez auto-selection is still broken.** Scenario living heals are much safer than 3.00; rez and scenario HP freshness need another pass.

## Claimed fixes re-verified

| Prior | Topic | 3.04 |
|---|---|---|
| #3 | Hotbar slot 118 CD probe | Replaced write, but see Critical below |
| #4 | Scenario/siege roster | Fallthrough + `.health` + realm soft-filter OK vs stock `ScenarioGroupWindow` |
| #5 | Empty friendly = self | Fixed (`GetFriendlyTarget` returns `L""`) |
| #6 | Frozen local name | Fixed (`refreshLocalPlayerName`) |
| #7 | Ctrl+click fires action | Fixed (early `return`) |
| #8 | Config nil / unclamped | Fixed (`clampConfigNumber` + `NormalizeSettings`) |
| #9 | Friend bias vs rez-safety | Fixed (rez uses real HP) |
| #10 | Warband auto-target slots | Fixed (self skipped in `memberSlot`) |
| #11 | `SetPlayersLOS` nil | Fixed |

## Critical

### C1 — `GetAbilityCooldown` is duration, not remaining CD

**Issue:** [#12](https://github.com/Talladego/WarTriage/issues/12)

`IsActionOnCooldown` uses `GetAbilityCooldown(id)/1000 > 0.1`. Stock tooltips use that API for ability **cooldown length**. Rez abilities always report a large duration → `resOnCooldown` stuck true → dead targets never selected.

Remaining CD belongs to `GetHotbarCooldown(slot)` (current, max seconds). Need a safe remaining-CD path without stomping a player hotbar slot.

## High

### H1 — Scenario hit events ignored

**Issue:** [#13](https://github.com/Talladego/WarTriage/issues/13)

`SCENARIO_PLAYER_HITS_UPDATED` only dirties roster; ignores `(groupIndex, groupSlotNum, hits)`. HP can lag between full group refreshes (CustomUI merges hits for this reason).

## Summary issue

[#14](https://github.com/Talladego/WarTriage/issues/14) — `[quality] CODE_QUALITY 3.04 summary`

## Notes

- Repo label `severity:critical` was missing at review time; Critical filed with `severity:high` + `[critical]` title (same as 3.00).
- No application code changed in this docs PR.
