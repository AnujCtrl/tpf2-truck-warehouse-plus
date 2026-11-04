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
| Exits | everything leaves round one loop through the south gate | two exits: the north gate's outbound lane (never used by the original) and the loop to the south gate, ~10 terminals each |
| Storage | only what the cargo lanes give | **Storage** parameter: +0 / +500 / +1000 / **+2000** (default) / +5000 / +10000 cargo |
| Bay use | every truck queues for the one terminal its line stop names | **Spread trucks over all bays** (default Yes): a game script gives every line stop at the warehouse all other terminals as *alternative terminals*, bays first, so trucks take whichever bay is free |
| Construction files | 13 copies of the same script | thin wrappers around `res/scripts/truck_warehouse_plus/construction.lua` |

How the bays work: trucks come off the loop onto a one-way aisle in front of the hall, drive into
the east half of their bay, U-turn at the dock door and stop at the bay mouth facing out, so the trailer
sits backed onto the door. Road vehicles in TpF2 cannot reverse, so the U-turn is the price of the
realistic parked pose. The parking slots work the same way: in from the gate, U-turn at the fence end,
parked facing out (the first slot turns early, before the barrier bar over its far end).

Where they leave: each gate has one outbound lane onto your road, and that lane is what limits a busy
warehouse. TpF2 picks a truck's route by the fastest *planned* route, not by queues, so offering a choice
would send every truck the short way. The exits are therefore split by terminal:

- the other 10 bays (terminals 6–15): right turn onto an
  eastbound lane along the bay mouths, out through the **north gate** (the yard road was painted two-way
  all along; the original only drove in)
- the 3 westernmost bays (terminals 3–5): left turn onto a westbound lane along the bay mouths, north at
  the far end onto the loop, out through the **south gate**
- the 6 parking slots: west onto a collector that joins the loop's north road, out through the
  **south gate** (going out through the north gate would cross its incoming lane)
- the 2 lay-bys: the original loop, **south gate**

(1.0/1.1 sent every bay round the loop, 1.2 every bay through the north gate; each jammed its gate.)

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
  and can reach its own exit (east bays: only the north gate; west bays, parking and lay-bys: only the south gate), no truck dead ends, every cargo area reaches both sidewalks, the new lanes
  stay clear of the wall, islands, annex, barrier bar and fences and inside their own bay or slot, and all 13 constructions
  build 15 terminal groups with the selected storage.
- `lua5.2 test/auto_bays.lua`: the bay assignment (which terminals, hand-made stops left alone, old
  full lists extended, no re-sending), finding outdated warehouses, and the game script against a fake
  `api`, including the rebuild popup.
- `python -I tools/plot.py [out.png] [x0 x1 y0 y1]`: top-down plan of the meshes with the lanes drawn on
  top (run the tests first; they write `test/out/lanes.tsv`).
- Geometry constants (bay pitch, aisle, U-turn) live at the top of
  `res/scripts/truck_warehouse_plus/network.lua`; they were measured from the meshes.
