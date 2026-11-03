"""Top-down plan of the warehouse meshes with the lanes from test/out/lanes.tsv on top.

Run `lua5.2 test/run.lua` first, then:
    python -I tools/plot.py [out.png] [x0 x1 y0 y1]
Grey = model meshes, red = original truck lanes, blue = new truck lanes,
black/green = original/new cargo lanes, stars = terminal vehicle nodes (numbered).
"""
import re
import struct
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

ROOT = Path(__file__).resolve().parent.parent
MESH = ROOT / "res/models/mesh/dhltest"
out = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / "test/out/plan.png")
window = [float(v) for v in sys.argv[2:6]] if len(sys.argv) >= 6 else None


def mesh_triangles(name):
    text = (MESH / f"{name}.msh").read_text()
    blob = (MESH / f"{name}.msh.blob").read_bytes()
    va = text[text.index("vertexAttr"):]
    m = re.search(r"position\s*=\s*\{\s*count\s*=\s*(\d+),\s*numComp\s*=\s*3,\s*offset\s*=\s*(\d+)", va)
    count, off = int(m.group(1)), int(m.group(2))
    pos = struct.unpack_from(f"<{count // 4}f", blob, off)  # counts and offsets are in bytes
    subs = text[text.index("subMeshes"):text.index("vertexAttr")]
    tris = []
    for chunk in subs.split("indices")[1:]:
        m = re.search(r"position\s*=\s*\{\s*count\s*=\s*(\d+),\s*offset\s*=\s*(\d+)", chunk)
        n, io = int(m.group(1)) // 4, int(m.group(2))  # uint32 indices
        idx = struct.unpack_from(f"<{n}I", blob, io)
        for t in range(0, n - 2, 3):
            tris.append([(pos[3 * idx[t + k]], pos[3 * idx[t + k] + 1]) for k in range(3)])
    return tris


fig, ax = plt.subplots(figsize=(24, 15))
for name, col in (("dhl_gelaende", "#d8d8d8"), ("dhl_innen", "#cfd8ea"), ("dhl_linien", "#f0b060")):
    ax.add_collection(PolyCollection(mesh_triangles(name), facecolors="none", edgecolors=col, linewidths=0.4))

style = {("TRUCK", "orig"): ("red", 1.4), ("TRUCK", "new"): ("#1f5fff", 1.4),
         ("CARGO", "orig"): ("black", 0.8), ("CARGO", "new"): ("#00a000", 1.0)}
for line in (ROOT / "test/out/lanes.tsv").read_text().splitlines():
    parts = line.split("\t")
    if parts[0] == "TERMINAL":
        x, y = map(float, parts[2].split(","))
        ax.plot(x, y, "*", color="magenta", ms=14)
        ax.annotate(parts[1], (x, y), xytext=(3, 6), textcoords="offset points", fontsize=9, color="magenta")
        continue
    mode, origin, pts = parts
    xy = [tuple(map(float, p.split(","))) for p in pts.split()]
    col, lw = style[(mode, origin)]
    ax.plot([p[0] for p in xy], [p[1] for p in xy], color=col, lw=lw)

ax.set_aspect("equal")
if window:
    ax.set_xlim(window[0], window[1]); ax.set_ylim(window[2], window[3])
else:
    ax.autoscale()
ax.grid(True, lw=0.3)
fig.savefig(out, dpi=100, bbox_inches="tight")
print(out)
