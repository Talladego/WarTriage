# WarTriage

Healer triage addon for [Return of Reckoning](https://www.returnofreckoning.com/).

WarTriage creates a hotbar macro that targets the ally most in need of healing, with optional auto-target for your own party, resurrection awareness, Terror debuff handling, and Ctrl+click enable/disable on the macro button.

## Commands

- `/wt` or `/wartriage` — open config
- `/wt help` — command list
- `/wt toggle` — enable or disable
- `/wt settings` — print current settings
- `/wt buffs` — list effects on friendly target and self

## Requirements

Place the `WarTriage` folder in `Interface/AddOns/` and reload UI (`/ui`).

Dependencies (stock UI modules): `EA_ActionBars`, `EASystem_Utils`, `EASystem_TargetInfo`, `LibSlash`.

## Priority system (3.0)

Living targets are scored in one pool:

**selection score = urgency − (rank − 1) × crossover**

- **Urgency** — missing HP%, plus recent damage rate bonus, minus recent rez penalty
- **Rank (1–5)** — configurable per role: Self, Healer, Ranged DPS, Melee DPS, Tank (1 = heal first when similarly hurt)
- **Crossover** — how many urgency points each rank step is worth (default 15)

Only players below **hurt threshold** HP% are considered. Dead players use separate rez logic.

**Melee DPS:** Slayer, Marauder, Choppa, Witch Elf, White Lion, Witch Hunter  
**Ranged DPS:** Engineer, Squig Herder, Bright Wizard, Magus, Sorcerer, Shadow Warrior

## Current release

**3.04** — Correctness pass for issues #3–#11: rez CD via `GetAbilityCooldown` (no hotbar write), scenario/siege roster fallthrough + realm/health guards, empty friendly target no longer aliases self, refresh player name on load, Ctrl+click toggle returns without firing the button, config number clamp + `NormalizeSettings`, friend HP bias selection-only (not rez-safety), warband auto-target slots skip self, `SetPlayersLOS` nil-guards career LOS table.

**3.03** — Fix map-range name keys: use `fixString` (wstring, strip `^realm`) again so distance lookups match roster names. The 3.01 early-out incorrectly used `WStringToString`, which made everyone look OOR and blocked queueing/auto-target when range check was on.

**3.02** — OnUpdate: rez-cache / HP-history table walks run behind the 0.5 s decision gate (manual-override timer and clocks still every frame). Decay uses summed elapsed so hitch frames stay equivalent. Macro icon mute tint follows enabled+healer only (no longer grayed when no queued target).

**3.01** — `SetPlayersDistance` early-outs the overhead-map scan once every roster name has a distance. Skips the map loop entirely when range check is off.

**3.00** — Unified rank-based priority scoring (replaces per-role HP thresholds).
