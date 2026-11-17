"""Generate every pull-up bar.

    python3 pullup-bars/generator/build.py

Outputs (relative to pullup-bars/):
    roblox/PullUpBars.rbxmx           all nine tiers in one Folder
    roblox/models/<name>.rbxmx        one model per tier
    roblox/luau/Build_<name>.lua      command-bar build script per tier
    roblox/PullUpSystem.rbxmx         everything (scripts + bars) for InstallPullUpSystem.lua
    roblox/PullUpAnimation_*.rbxmx    the pull-up scripts, one file per service
    preview/index.html                3D web preview (open in a browser)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from emit import (model_name, model_node, preview_model, write_luau,  # noqa: E402
                  write_rbxmx, write_tree)
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

    scripts = os.path.join(ROOT, "roblox", "scripts")

    def src(*parts):
        with open(os.path.join(scripts, *parts), encoding="utf-8") as fh:
            return fh.read()

    shared = {"cls": "Folder", "name": "PullUp", "children": [
        {"cls": "ModuleScript", "name": "Config", "src": src("ReplicatedStorage", "PullUp", "Config.lua")},
        {"cls": "ModuleScript", "name": "PullUpRig", "src": src("ReplicatedStorage", "PullUp", "PullUpRig.lua")},
        {"cls": "ModuleScript", "name": "PullUpMotion",
         "src": src("ReplicatedStorage", "PullUp", "PullUpMotion.lua")},
    ]}

    def server(disabled=False):
        return {"cls": "Script", "name": "PullUpServer", "disabled": disabled,
                "src": src("ServerScriptService", "PullUpServer", "init.server.lua"), "children": [
                    {"cls": "ModuleScript", "name": "PullUpService",
                     "src": src("ServerScriptService", "PullUpServer", "PullUpService.lua")},
                    {"cls": "ModuleScript", "name": "PullUpBarShop",
                     "src": src("ServerScriptService", "PullUpServer", "PullUpBarShop.lua")},
                ]}
    client = {"cls": "LocalScript", "name": "PullUpClient",
              "src": src("StarterPlayerScripts", "PullUpClient.client.lua")}
    bars = {"cls": "Folder", "name": "PullUpBars",
            "children": [model_node(t, n, p) for t, n, _, p in built]}

    out = os.path.join(ROOT, "roblox")
    write_tree(os.path.join(out, "PullUpAnimation_ReplicatedStorage.rbxmx"), [shared])
    write_tree(os.path.join(out, "PullUpAnimation_ServerScriptService.rbxmx"), [server()])
    write_tree(os.path.join(out, "PullUpAnimation_StarterPlayerScripts.rbxmx"), [client])
    # Everything in one file. The server script is disabled until the installer
    # moves it into ServerScriptService, so nothing runs from Workspace.
    write_tree(os.path.join(out, "PullUpSystem.rbxmx"), [{"cls": "Folder", "name": "PullUpSystem", "children": [
        {"cls": "Folder", "name": "ReplicatedStorage", "children": [shared]},
        {"cls": "Folder", "name": "ServerScriptService", "children": [server(disabled=True)]},
        {"cls": "Folder", "name": "StarterPlayerScripts", "children": [client]},
        {"cls": "Folder", "name": "ServerStorage", "children": [bars]},
    ]}])

    # the preview plays frames exported by tests/sim.luau (the real Luau code)
    anim_path = os.path.join(ROOT, "preview", "animation.json")
    anim = "null"
    if os.path.exists(anim_path):
        with open(anim_path, encoding="utf-8") as fh:
            anim = fh.read().strip()

    data = json.dumps([preview_model(t, n, s, p) for t, n, s, p in built], separators=(",", ":"))
    with open(os.path.join(HERE, "preview_template.html"), encoding="utf-8") as fh:
        html = fh.read().replace("/*__MODELS__*/", data).replace("/*__ANIMATION__*/", anim)
    with open(os.path.join(ROOT, "preview", "index.html"), "w", encoding="utf-8") as fh:
        fh.write(html)


if __name__ == "__main__":
    main()
