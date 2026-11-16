"""Generate every pull-up bar.

    python3 pullup-bars/generator/build.py

Outputs (relative to pullup-bars/):
    roblox/PullUpBars.rbxmx           all nine tiers in one Folder
    roblox/models/<name>.rbxmx        one model per tier
    roblox/luau/Build_<name>.lua      command-bar build script per tier
    preview/index.html                3D web preview (open in a browser)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from emit import model_name, preview_model, write_luau, write_rbxmx  # noqa: E402
from themes import TIERS  # noqa: E402

ROOT = os.path.dirname(HERE)


def main():
    built = []
    for tier, name, fn, sky in TIERS:
        b = fn()
        built.append((tier, name, sky, b.parts))
        n_neon = sum(1 for p in b.parts if p["mat"] == "Neon")
        print("T%d %-12s %4d parts (%d neon)" % (tier, name, len(b.parts), n_neon))

    os.makedirs(os.path.join(ROOT, "roblox", "models"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "roblox", "luau"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "preview"), exist_ok=True)

    write_rbxmx(os.path.join(ROOT, "roblox", "PullUpBars.rbxmx"),
                [(t, n, p) for t, n, _, p in built], folder="PullUpBars")
    for t, n, _, p in built:
        mn = model_name(t, n)
        write_rbxmx(os.path.join(ROOT, "roblox", "models", mn + ".rbxmx"), [(t, n, p)])
        write_luau(os.path.join(ROOT, "roblox", "luau", "Build_" + mn + ".lua"), t, n, p)

    data = json.dumps([preview_model(t, n, s, p) for t, n, s, p in built], separators=(",", ":"))
    with open(os.path.join(HERE, "preview_template.html"), encoding="utf-8") as fh:
        html = fh.read().replace("/*__MODELS__*/", data)
    with open(os.path.join(ROOT, "preview", "index.html"), "w", encoding="utf-8") as fh:
        fh.write(html)


if __name__ == "__main__":
    main()
