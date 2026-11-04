# Truck warehouse Plus (Transport Fever 2)

A fork of **LKW Warenlager / Truck distribution center** by **rob (Robconstrictor)**, script by
**RPGFabi** and **elektronikfreak**, Steam Workshop item
[2456822185](https://steamcommunity.com/sharedfiles/filedetails/?id=2456822185) (2021).
The model, textures and all 13 company variants are theirs. The original author said on the Workshop page
that the few terminals were a known problem; this fork fixes that.

## What changed

| | Original | Plus |
|---|---|---|
| Terminals | 2 lay-bys on the south road | the same 2 (still terminals 1 and 2) **+ 13 loading bays** (terminals 3–15), one per painted bay and dock door on the hall's north side, **+ 6 truck parking slots** (terminals 16–21) inside the north gate |
| Gates | two-way, one lane each way; everything in at the north gate and out round a one-lane loop through the south gate | both gates one-way, two lanes: in at the north gate, out at the south gate, two-lane loop in between; bays on one lane, lay-bys and parking on the other |
| Storage | only what the cargo lanes give | **Storage** parameter: +0 / +500 / +1000 / **+2000** (default) / +5000 / +10000 cargo |
| Bay use | every truck queues for the one terminal its line stop names | **Spread trucks over all bays** (default Yes): a game script gives every line stop at the warehouse all other terminals as *alternative terminals*, bays first, so trucks take whichever bay is free |
| Construction files | 13 copies of the same script | thin wrappers around `res/scripts/truck_warehouse_plus/construction.lua` |

How the bays work: trucks come off the loop onto a one-way aisle in front of the hall, drive into
the east half of their bay, U-turn at the dock door and stop at the bay mouth facing out, so the trailer
sits backed onto the door. Road vehicles in TpF2 cannot reverse, so the U-turn is the price of the
realistic parked pose. The parking slots work the same way: in from the gate, U-turn at the fence end,
parked facing out (the first slot turns early, before the barrier bar over its far end).

Gates and the loop (1.5): both gate stubs are **one-way two-lane roads**. The north gate is the way
**in** on both lanes, the south gate the way **out** on both lanes, and the loop round the building is two
lanes from where the bays join it to the south gate. Each stream keeps its own lane all the way:

| | way in (north gate) | way out |
|---|---|---|
| 13 loading bays | south lane → yard road → aisle | west along the bay mouths → loop, inner lane → south gate, inner lane |
| 6 parking slots | north lane → round the gate island | collector → loop, outer lane → south gate, outer lane |
| 2 lay-bys | north lane → loop, outer lane | loop, outer lane → south gate, outer lane |

TpF2 routes trucks by the fastest *planned* route, not by queues, and model lanes have no lane
changing, so two parallel lanes are only both used when different traffic is assigned to each; hence
the split above. Which gate lane a truck actually arrives in is up to your roads, though: in 1.5 every
truck turning in from the main road landed in the north lane and the bays' exit lane fed straight back
into the entrance, so trucks left and came back in. Since 1.6 an **X of crossovers just inside each
gate** lets either lane reach every terminal and either exit lane. The direct lane stays the shorter
route (by about 1 m), so trucks only cross over when the street left them in the other lane.

**Your roads must match:** connect the north gate with a road that runs one-way *into* the gate and the
south gate with a road that runs one-way *out of* it (e.g. *Two-lane one-way road*). A two-way road
on either gate leaves one of its lanes facing the wrong way.

(1.0 sent every bay round a single-lane loop, 1.2 every bay out through the north gate, 1.3 split them
between the gates; each jammed a single lane.)

Cargo for each bay waits on a short lane behind its door, connected through a corridor inside the hall to
the original cargo network and both street sidewalks, so transfers between terminals work.

Spreading over the bays uses the game's own *alternative terminals* (line window, per stop). Every
~2 seconds `res/config/game_script/truck_warehouse_plus.lua` looks for line stops at a warehouse whose
alternative-terminal list is still **empty** and fills it. A list that is "every other terminal" of a
smaller, older warehouse is extended when the warehouse grows; any other list you picked yourself is
never changed. Set **Spread trucks over all bays** to *No* on a warehouse to leave its lines alone. The
game log shows a `truck_warehouse_plus: line … alternative terminals added` line for every line it updates.

## Install

1. In the game's mod list, **disable the Workshop original**: this fork uses the same file paths so
   that warehouses already in your saves keep working, and the two must not be active together.
2. `./install.sh` (game closed) copies the mod to the local mods folder as `truck_warehouse_plus_1`.
3. Enable *Truck warehouse Plus* for the save.

Existing warehouses keep their original two terminals as terminals 1 and 2, and new terminals are always
appended, so lines stay valid. A warehouse keeps the lanes it was built with until it is rebuilt: when a
save has warehouses from an older version, a **popup at the start** offers to rebuild them (same settings,
lines stay attached). You can also rebuild one by changing any of its settings.

## Development

- `lua5.2 test/run.lua`: checks (headless, against the game's own `res/scripts`):
  the original network is preserved, all indices are valid, every terminal is reachable from the entrance
  and can reach its own way out (bays: the gates' south/inner lanes only; parking and lay-bys: the north/outer lanes only), no truck dead ends, new lanes keep a truck width from the original loop, every cargo area reaches both sidewalks, the new lanes
  stay clear of the wall, islands, annex, barrier bar and fences and inside their own bay or slot, and all 13 constructions
  build 15 terminal groups with the selected storage.
- `lua5.2 test/auto_bays.lua`: the bay assignment (which terminals, hand-made stops left alone, old
  full lists extended, no re-sending), finding outdated warehouses, and the game script against a fake
  `api`, including the rebuild popup.
- `python -I tools/plot.py [out.png] [x0 x1 y0 y1]`: top-down plan of the meshes with the lanes drawn on
  top (run the tests first; they write `test/out/lanes.tsv`).
- Geometry constants (bay pitch, aisle, U-turn) live at the top of
  `res/scripts/truck_warehouse_plus/network.lua`; they were measured from the meshes.
