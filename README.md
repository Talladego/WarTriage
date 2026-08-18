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

**3.00** — Unified rank-based priority scoring (replaces per-role HP thresholds).
