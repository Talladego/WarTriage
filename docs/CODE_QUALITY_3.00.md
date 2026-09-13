# WarTriage Code Quality Report

**Version:** **3.00**  
- `WarTriage.mod` UiMod: `version="3.00"` (date `2026-07-11`, `gameVersion="1.4.8"`)  
- `WarTriage.lua`: `local VERSION = 3.00`  
- `README.md`: current release **3.00**

**Scope:** Report only. No application code was changed and no fix PR was opened. Reviewed `WarTriage.lua` (~2,500 lines), `WarTriage_Config.lua`, `WarTriage.mod`, `README.md`, and vendored `libs/LibConfig.lua` / `LibGUI.lua` / `LibStub.lua`.

---

## Overall verdict

The 3.00 rank/urgency scoring is coherent, settings migration exists, and there is real production thinking (rez cache, terror, manual lock, macro repair, dirty-flag refresh). It is still **not production-safe for its main job** (scenario / siege healing). The scenario snapshot path is structurally wrong or incomplete, a cooldown probe writes a real hotbar slot every 0.5s, and several targeting predicates treat “no target” and “self” as the same thing.

**Verdict: needs targeted correctness fixes before 3.00 is trustworthy in scenarios.** Party-only play with range check on is in better shape.

---

## Critical

### 1. Cooldown probe overwrites a real hotbar slot (and can GCD)

`WarTriage.lua` (`IsActionOnCooldown`, `TEST_BARSLOT = 118`)

Every `GetHurtPlayer()` pass (about every 0.5s while active) does:

```lua
SetHotbarData(TEST_BARSLOT, GameData.PlayerActions.DO_ABILITY, actionId)
local cd = GetHotbarCooldown(TEST_BARSLOT)
```

Slot 118 is action bar 10, button 10 — a normal player slot. This repeatedly replaces whatever is there with the rez ability.

On Return of Reckoning, `SetHotbarData` in combat has historically applied a **3s global cooldown**. Calling it twice a second while healing would make the addon fight the healer.

`GetHurtPlayer()` is the only caller; rez CD is the only reason this runs.

---

### 2. Scenario / siege roster is not a safe friendly list

`WarTriage.lua` — `BuildFriendlyPlayersSnapshot()`

```lua
if (GameData.Player.isInScenario or GameData.Player.isInSiege) and GameData.GetScenarioPlayerGroups then
    local scenarioPlayers = GameData.GetScenarioPlayerGroups() or {}
    -- uses playerData.name / playerData.health / playerData.careerId
elif IsWarBandActive() then
    -- warband
else
    -- party
end
```

Problems stacked on one branch:

| Risk | Effect |
|---|---|
| Function name is **Groups**, not a flat player list | `ipairs` may walk group tables with no `.name` → only **self** is tracked in scenarios |
| RoR wiki lists `GameData.GetScenarioPlayers()`, not `GetScenarioPlayerGroups` | Wrong or empty API |
| No `realm` filter | If the table is flat and includes both teams, enemies become heal/rez candidates |
| `health` vs party/warband `healthPercent` | `clampHealthPercent(nil)` → **100%**. Everyone looks full; living targets never beat `hurtThreshold` (`100 < 100` is false) |
| `ORDER_ARMY` and `DESTRUCTION_ARMY` are both in `MapPointTypeFilter` | Enemies can get real distances |
| `rangeCheck == false` forces `distance = 0` | Makes wrong-realm / unknown-range players look in range |
| `isInSiege` takes this exclusive branch even when the table is empty | City siege + warband can drop the entire warband and leave **only self** |

This is the core PvP path. Party/warband APIs are not used as fallback once this `if` is entered.

---

## High

### 3. Empty friendly target is treated as “already targeting self”

`WarTriage.lua` — `GetFriendlyTarget()`, `TargetPlayer()`

When `entityid == 0` (no friendly target), the code sets `PlayerTarget` to the local player.

`TargetPlayer()` then does: if suggested name == `PlayerTarget`, **clear the macro** instead of arming it.

If you are the best heal and have no target, the addon will not queue self on the macro and will not fire `TARGET_SELF` auto-target. Self-triage silently does nothing.

---

### 4. Player name is frozen at file load

`WarTriage.lua` line 21:

```lua
local LOCAL_PLAYER_NAME = GameData.Player.name
```

`LOADING_END` and snapshots only do `fixString(LOCAL_PLAYER_NAME)` — they never reread `GameData.Player.name`. If the name is empty or still has a grammar suffix at parse time, self, party maps, and “already targeted” checks stay wrong for the session.

---

### 5. Ctrl+click toggle still fires the button action

`WarTriage.lua` — `installActionButtonHooks()`

```lua
if isWarTriageMacroButton(self) and flags == SystemData.ButtonFlags.CONTROL then
    WarTriage.ToggleEnabled()
end
orgActionButtonOnLButtonDown(self, flags, x, y)  -- always runs
```

Ctrl+click both toggles the addon **and** performs SET_TARGET / the default click. Enabling can instantly change target; disabling can still fire the queued target.

---

### 6. Config save can persist `nil` / unclamped numbers

`WarTriage_Config.lua` textboxes for `hurtThreshold`, `rezSafetyThreshold`, `rankCrossover`, `manualOverrideDuration` have **no** `LibConfig.MinMax` (or other) callbacks.

`libs/LibConfig.lua` `Save()` does `tonumber(newValue)` for numeric settings. `""` or `"abc"` becomes `nil` and is written into `WarTriage.Settings`. `SettingsChanged()` does not call `normalizeSettings()`.

Until `/reloadui`, thresholds and crossover can be nil/out of range. `LibConfig.MinMax` already exists in that library and is unused.

---

### 7. Friend HP bias also drives rez-safety blocking

`WarTriage.lua` — `getSelectionHealthWithFriendBias()`, `livingPlayerBlocksRez()`, `GetHurtPlayer()`

Favor Friends multiplies HP by 0.75 for selection **and** for `livingPlayerBlocksRez()`. A friend at 92% real HP looks like 69% and can block all rez picks against a ~90% safety floor, while actually healthy.

Self is excluded from the bias; everyone else is not.

---

### 8. Warband auto-target slot indexing is likely wrong

`WarTriage.lua` — `getOwnPartyTargetEvents()`

Warband branch: `ipairs(warbandParty.players)` → `PartyTargetEvent[index]` (`TARGET_GROUP_MEMBER_1`–`6`).

Stock `GetPartyData()` is usually “everyone except you,” so index 1 = member 1. Warband `players` usually **includes self**. Then:

- self at index 1 is remapped to `TARGET_SELF` (OK)
- the next member gets `TARGET_GROUP_MEMBER_2` while the client slot is still `TARGET_GROUP_MEMBER_1`

Auto-target can hit the wrong party member. Regular party path is much safer.

---

### 9. `SetPlayersLOS` can nil-index and Lua-error

`WarTriage.lua` — `SetPlayersLOS()`

```lua
local checkAbilityID = LosCheckAbiliyId[GameData.Player.career.line]
-- later, unguarded:
players[i].hasLOS = IsTargetValid(checkAbilityID.healID)
```

`GetHurtPlayer()` null-checks the same table. `SetPlayersLOS()` does not. If `career.line` is 0 / unknown during load, or `losCheck` is on before career is ready, this throws and stops the 0.5s update loop.

---

## Medium

### 10. Manual lock never releases on high HP

`MANUAL_OVERRIDE_RELEASE_PCT = 90` is defined in `WarTriage.lua` and **never used**. Lock only expires on the timer. A topped-off lock still pauses all triage for the full duration. Incomplete feature, not a dead constant by accident.

---

### 11. LOS is “last targeted player only”

`SetPlayersLOS()` documents this: everyone else is `hasLOS = true` until they become the friendly target. First click can be a hard LOS fail; the next click then skips them. Fine as a limitation, easy to mistake for random skips.

---

### 12. Distance = 999999 if the player is missing from the overhead map

`SetPlayersDistance()` walks `GetMapPointData("EA_Window_OverheadMapMapDisplay", 1..511)`. Indoor / instance / missing pip ⇒ out of range. Default `rangeCheck` is on, so those allies are dropped.

---

### 13. Performance: 511 map-point reads + macro rebuild every 0.5s

On the throttled tick (`TIME_DELAY = 0.5`):

- 511 `GetMapPointData` calls  
- `GetMacrosData` / `GetMacroSlots` (all bars × buttons) via `SetMacroTarget` → `ensureMacroAvailable`  
- `GetIgnoreList` / `GetFriendsList` / `GetBuffs` when those options are on  
- `SetHotbarData` (see Critical)

`OnUpdate` also runs **every frame**: rez-cache cleanup, HP-history decay, history sweep, manual-lock timer. Cheap compared to the map loop, but unnecessary at frame rate.

Trace log uses `table.remove(entries, 1)` at 150 entries (O(n) per append). Debug-only.

---

### 14. Config window layout / paging

`WarTriage_Config.lua` `resizeConfigWindow()` resizes the frame to 860×620 but **not** LibConfig layers (created at 700×550). Content stays in the old inner box.

Settings has 11 controls; LibConfig paginates at **10** (`libs/LibConfig.lua`). **Manual lock duration is on page 2** behind `>>`. Easy to never see.

---

### 15. One 2,500-line file; unused API

`WarTriage.lua` mixes scoring, snapshots, macros, tooltips (~300 lines), hooks, and debug. Hard to test.

Unused: `hasBuff`, `osDate`, `WarTriage.GetFriendlyPlayers`, `MANUAL_OVERRIDE_RELEASE_PCT`. Tooltip dump uses `tostring()` on wstrings (`DumpTraceLog`) — often garbage in WAR Lua.

Typo: `LosCheckAbiliyId`.

---

### 16. Rez pending IDs may be wrong

`REZ_PENDING_EFFECT_IDS` uses **cast** ability IDs. Comments in `WarTriage.lua` say to discover corpse buff IDs with `/wt buffs`. If those differ, pending-rez detection fails and the addon will keep suggesting already-rezzed corpses.

Terror match includes `iconNum == 2572`, which can false-positive other effects with that icon.

---

### 17. Vendored LibConfig/LibGUI issues that affect this addon

`libs/LibConfig.lua`: nil-on-bad-number save (above); `OnUpdate` tints `colorizer.object` with no nil guard (WarTriage does not use color pickers).  
`libs/LibGUI.lua`: `elementCount` increments even when window create returns nil.

---

## Low

- `sortTrackedPlayers()` is unused by scoring (`GetHurtPlayer` uses scores). Sort can throw if `distance` were ever nil (`k1.distance < k2.distance`).
- `isHealer` is a saved setting overwritten by `CheckCareer()`. Career change without `LOADING_END` can leave the addon dormant or active incorrectly. Macro create on healer-respec waits for the 5s watchdog / first active `OnUpdate`.
- `ignoreIgnoredPlayers` also excludes those players from rez-safety scans (an ignored 20% ally will not block a rez).
- Saved-variable leftovers (`playerTargetPct`, etc.) are never stripped after migration.
- No automated tests; no validation that career IDs / rez effect IDs still match 1.4.8.
- `WarTriage.Disable()` prints `--- <icon58> Enabled` (same label as the enabled line, icon off). Confusing, not broken.
- `.mod` `savedVariablesVersion` is still `"2.0"` while the addon is 3.00 (intentional if they rely on `migrateSettings`).

---

## What is in good shape

- Rank score `urgency − (rank − 1) × crossover` matches the README and is applied consistently for living targets.
- Settings merge + 3.00 migration (`playerTargetPct` → `hurtThreshold`, default ranks).
- Dirty flags + snapshot vs transient split (HP/roster vs range/LOS).
- Self HP from scenario is not allowed to overwrite a lower local HP (`shouldIgnoreHealthMerge`).
- Macro missing / full / unplaced warnings and periodic repair.
- Terror + rez-block cache with duration fallbacks.
- Event handlers unregistered when disabled; `OnUpdate` early-outs when not a healer.

---

## Top fixes (priority order)

1. **Remove `SetHotbarData(118)`.** Read rez cooldown without touching a visible slot (and never from combat). If a probe slot is unavoidable, use a non-UI slot and restore it; do not write every 0.5s.
2. **Fix the scenario/siege snapshot.** Confirm the real API (`GetScenarioPlayers` vs groups). Flatten groups if needed. Filter `player.realm == GameData.Player.realm`. Use the correct HP field (`health` vs `healthPercent`). If the list is empty in a siege, fall through to warband/party — do not keep an exclusive empty branch.
3. **Stop aliasing “no target” to self** in `GetFriendlyTarget()` / `TargetPlayer()`. Empty target should still allow self to be queued or auto-targeted.
4. **Refresh name from `GameData.Player.name` in `LOADING_END` and each snapshot**, not from a load-time local.
5. **Validate settings on save** (`LibConfig.MinMax` / `normalizeSettings()` in `SettingsChanged`). Reject nil numbers.
6. **Ctrl+click:** toggle and `return` — do not call the original `OnLButtonDown`.
7. **Rez safety must use real HP**, not friend-biased HP.
8. **Warband auto-target:** map `TARGET_GROUP_MEMBER_*` by party slot (excluding self), not raw `ipairs` index.
9. **Nil-guard `LosCheckAbiliyId`** in `SetPlayersLOS` the same way as `GetHurtPlayer`.
10. **Implement or delete `MANUAL_OVERRIDE_RELEASE_PCT`.** Put lock duration on the first Settings page (or raise LibConfig’s page size). Avoid 511 map scans every tick if a cheaper range source exists.

---

**Files:** `WarTriage.lua` holds almost every functional issue. `WarTriage_Config.lua` is validation/layout. `libs/LibConfig.lua` is the nil-number save. `WarTriage.mod` version string is **3.00**.