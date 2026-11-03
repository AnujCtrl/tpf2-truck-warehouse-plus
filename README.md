# Truck warehouse Plus (Transport Fever 2)

A fork of **LKW Warenlager / Truck distribution center** by **rob (Robconstrictor)**, script by
**RPGFabi** and **elektronikfreak**, Steam Workshop item
[2456822185](https://steamcommunity.com/sharedfiles/filedetails/?id=2456822185) (2021).
The model, textures and all 13 company variants are theirs. The original author said on the Workshop page
that the few terminals were a known problem; this fork fixes that.

## What changed

| | Original | Plus |
|---|---|---|
| Terminals | 2 lay-bys on the south road | the same 2 (still terminals 1 and 2) **+ 13 loading bays** (terminals 3–15), one per painted bay and dock door on the hall's north side |
| Storage | only what the cargo lanes give | **Storage** parameter: +0 / +500 / +1000 / **+2000** (default) / +5000 / +10000 cargo |
| Construction files | 13 copies of the same script | thin wrappers around `res/scripts/truck_warehouse_plus/construction.lua` |

How the bays work: trucks come off the loop onto a one-way aisle in front of the hall, drive into
the east half of their bay, U-turn at the dock door and stop at the bay mouth facing out, so the trailer
sits backed onto the door. They leave west along the aisle and rejoin the loop's north road.
Road vehicles in TpF2 cannot reverse, so the U-turn is the price of the realistic parked pose.

Cargo for each bay waits on a short lane behind its door, connected through a corridor inside the hall to
the original cargo network and both street sidewalks, so transfers between terminals work.

## Install

1. In the game's mod list, **disable the Workshop original**: this fork uses the same file paths so
   that warehouses already in your saves keep working, and the two must not be active together.
2. `./install.sh` (game closed) copies the mod to the local mods folder as `truck_warehouse_plus_1`.
3. Enable *Truck warehouse Plus* for the save.

Existing warehouses keep their original two terminals as terminals 1 and 2, so their lines stay valid.

## Development

- `lua5.2 test/run.lua`: checks (headless, against the game's own `res/scripts`):
  the original network is preserved, all indices are valid, every terminal is reachable from the entrance
  and can reach the exit, no truck dead ends, every cargo area reaches both sidewalks, the new lanes
  stay clear of the wall, island, annex and fence and inside their own bay, and all 13 constructions
  build 15 terminal groups with the selected storage.
- `python -I tools/plot.py [out.png] [x0 x1 y0 y1]`: top-down plan of the meshes with the lanes drawn on
  top (run the tests first; they write `test/out/lanes.tsv`).
- Geometry constants (bay pitch, aisle, U-turn) live at the top of
  `res/scripts/truck_warehouse_plus/network.lua`; they were measured from the meshes.
