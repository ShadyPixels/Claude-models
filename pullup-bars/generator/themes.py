"""The nine pull-up bars, one per treadmill tier in the reference video.

Each theme reuses the same functional frame (base, two posts, header beam and
grip bar at identical heights so gameplay code works for every tier) and then
adds the decoration that matches its treadmill.
"""
from __future__ import annotations

import math

from core import (Builder, bolt, bone, chain, cloud, crown, crystal, fan, gem, mini_skull,
                  mix, ring, rubble, skull, specks, spire, wing, x_panel)

# --------------------------------------------------------------------------
# Shared dimensions (studs)
# --------------------------------------------------------------------------
POST_X = 4.5          # posts sit at x = +/-POST_X
BASE_Y = 0.6          # top of the base plate
POST_TOP = 10.6       # top of the posts
HEADER_Y = 11.2       # header beam centre
HEADER_TOP = 11.8
BAR_Y = 9.2           # grip bar height
BAR_Z = -1.6          # grip bar sits in front of the posts
GRIP_X = 2.0          # hand positions (+/-), a wide overhand grip
HANG_Y = BAR_Y - 4.0  # where the HumanoidRootPart should sit while hanging


# --------------------------------------------------------------------------
# Particle / light presets (converted to Roblox properties by emit.py)
# --------------------------------------------------------------------------

def light(color, brightness=2.0, rng=14):
    return {"color": color, "brightness": brightness, "range": rng}


def sparkles(c1, c2=None, rate=8, size=0.35, life=(1.2, 2.2), speed=(0.5, 1.5),
             accel=(0, 0.6, 0), spread=(180, 180)):
    return {"texture": "sparkles", "colors": [c1, c2 or c1], "rate": rate,
            "size": [(0, size), (1, 0)], "transparency": [(0, 0.1), (1, 1)],
            "lifetime": life, "speed": speed, "accel": accel, "spread": spread,
            "light_emission": 1, "rotspeed": (-90, 90)}


def embers(c1, c2, rate=18, size=0.28):
    return {"texture": "sparkles", "colors": [c1, c2], "rate": rate,
            "size": [(0, size), (1, 0.05)], "transparency": [(0, 0), (0.8, 0.3), (1, 1)],
            "lifetime": (1.0, 2.0), "speed": (1.5, 3.5), "accel": (0, 2.5, 0),
            "spread": (25, 25), "light_emission": 1, "rotspeed": (-180, 180)}


def flame(c1, c2, rate=22, size=0.9):
    return {"texture": "fire", "colors": [c1, c2], "rate": rate,
            "size": [(0, size), (1, 0.1)], "transparency": [(0, 0.2), (1, 1)],
            "lifetime": (0.4, 0.8), "speed": (1.5, 2.5), "accel": (0, 3, 0),
            "spread": (10, 10), "light_emission": 1, "rotspeed": (-60, 60)}


def snow(c1, rate=10):
    return {"texture": "sparkles", "colors": [c1, "#ffffff"], "rate": rate,
            "size": [(0, 0.25), (1, 0.15)], "transparency": [(0, 0.2), (1, 1)],
            "lifetime": (2.5, 4.0), "speed": (0.2, 0.6), "accel": (0, -0.8, 0),
            "spread": (180, 180), "light_emission": 0.6, "rotspeed": (-45, 45)}


def drips(c1, rate=6):
    return {"texture": "sparkles", "colors": [c1, mix(c1, "#000000", 0.4)], "rate": rate,
            "size": [(0, 0.25), (1, 0.12)], "transparency": [(0, 0), (1, 0.8)],
            "lifetime": (1.0, 1.6), "speed": (0, 0.2), "accel": (0, -6, 0),
            "spread": (0, 0), "light_emission": 0.8, "rotspeed": (0, 0)}


def bubbles(c1, rate=10):
    return {"texture": "sparkles", "colors": [c1, mix(c1, "#ffffff", 0.5)], "rate": rate,
            "size": [(0, 0.15), (0.5, 0.4), (1, 0.05)], "transparency": [(0, 0.3), (1, 1)],
            "lifetime": (1.5, 3.0), "speed": (0.5, 1.2), "accel": (0, 1.2, 0),
            "spread": (30, 30), "light_emission": 1, "rotspeed": (-30, 30)}


def sparks(c1, rate=14):
    return {"texture": "sparkles", "colors": [c1, "#ffffff"], "rate": rate,
            "size": [(0, 0.45), (1, 0)], "transparency": [(0, 0), (1, 1)],
            "lifetime": (0.25, 0.6), "speed": (4, 8), "accel": (0, 0, 0),
            "spread": (180, 180), "light_emission": 1, "rotspeed": (-360, 360)}


def fx(b, name, pos, size, emitter, lt=None):
    """Invisible part that owns a particle emitter (and optional light)."""
    with b.in_group("FX"):
        b.box(name, pos, size, "#ffffff", "SmoothPlastic", transparency=1, shadow=False,
              emitter=emitter, light=lt)


# --------------------------------------------------------------------------
# Shared frame
# --------------------------------------------------------------------------

def frame(b: Builder, t: dict):
    """Functional skeleton shared by every tier. Same heights everywhere so the
    pull-up animation/script lines up on all nine bars."""
    pw = t.get("post_w", 1.0)
    dark, light_c = t["dark"], t["light"]
    trim, glow = t["trim"], t["glow"]
    fmat = t.get("frame_mat", "Metal")

    with b.in_group("Frame"):
        base = b.box("Base", (0, 0.3, 0), (11.0, 0.6, 7.0), t.get("base", dark),
                     t.get("base_mat", fmat), collide=True,
                     attachments=[("HangPoint", (0, HANG_Y, BAR_Z)),
                                  ("StandPoint", (0, BASE_Y + 0.12, BAR_Z)),
                                  ("EnterPoint", (0, BASE_Y, -4.6))])
        base["primary"] = True
        b.box("Mat", (0, BASE_Y + 0.06, -0.6), (6.4, 0.12, 5.0), t.get("mat", "#1b1d22"),
              "Fabric", collide=True)

        for sx in (-1, 1):
            x = sx * POST_X
            # foot beam + glowing end caps
            b.box("Foot", (x, BASE_Y + 0.4, 0), (1.5, 0.8, 6.6), dark, fmat, collide=True)
            for sz in (-1, 1):
                b.box("FootCap", (x, BASE_Y + 0.45, sz * 3.25), (1.6, 1.0, 0.5), trim,
                      t.get("trim_mat", "Metal"))
                b.neon("FootGlow", (x, BASE_Y + 0.45, sz * 3.52), (1.0, 0.6, 0.06), glow)
            # post: dark lower, lighter upper
            b.box("Post", (x, BASE_Y + 2.5, 0), (pw, 5.0, pw), dark, fmat, collide=True)
            b.box("Post", (x, BASE_Y + 7.5, 0), (pw * 0.9, 5.0, pw * 0.9), light_c,
                  t.get("light_mat", fmat), collide=True)
            b.box("Collar", (x, BASE_Y + 5.0, 0), (pw + 0.2, 0.4, pw + 0.2), trim,
                  t.get("trim_mat", "Metal"))
            # neon strip on the inside and front face of each post
            b.neon("PostGlow", (x - sx * (pw / 2 + 0.03), BASE_Y + 5.0, 0), (0.06, 8.6, 0.25),
                   glow)
            b.neon("PostGlow", (x, BASE_Y + 5.0, -(pw / 2 + 0.03)), (0.25, 8.6, 0.06), glow)
            # arm that holds the grip bar
            b.box("BarArm", (x, BAR_Y, (BAR_Z - pw / 2) / 2 - 0.1), (0.7, 0.7, abs(BAR_Z) + 0.4),
                  trim, t.get("trim_mat", "Metal"), collide=True)
            b.box("BarArmCap", (x, BAR_Y, BAR_Z), (0.9, 0.9, 0.9), dark, fmat, collide=True)
            b.neon("BarArmGlow", (x, BAR_Y, BAR_Z - 0.47), (0.5, 0.5, 0.06), glow)

        # base trim
        for sz in (-1, 1):
            b.neon("BaseGlow", (0, BASE_Y - 0.15, sz * 3.53), (9.0, 0.14, 0.08), glow)
        for sx in (-1, 1):
            b.neon("BaseGlow", (sx * 5.53, BASE_Y - 0.15, 0), (0.08, 0.14, 6.0), glow)

        # header beam
        b.box("Header", (0, HEADER_Y, 0), (10.6, 1.2, 1.4), dark, fmat, collide=True)
        b.box("HeaderTrim", (0, HEADER_TOP + 0.1, 0), (10.9, 0.2, 1.6), trim,
              t.get("trim_mat", "Metal"))
        b.neon("HeaderGlow", (0, HEADER_Y - 0.25, -0.73), (9.2, 0.14, 0.06), glow)
        b.neon("HeaderGlow", (0, HEADER_Y + 0.25, -0.73), (9.2, 0.14, 0.06), glow)

        # the grip bar itself (collidable, carries the hand attachments)
        b.cyl("GripBar", (0, BAR_Y, BAR_Z), 9.0, 0.42, t.get("bar", "#c8ced6"),
              t.get("bar_mat", "Metal"), collide=True,
              attachments=[("GripLeft", (-GRIP_X, BAR_Y, BAR_Z)),
                           ("GripRight", (GRIP_X, BAR_Y, BAR_Z))])
        for sx in (-1, 1):
            b.cyl("Grip", (sx * GRIP_X, BAR_Y, BAR_Z), 1.3, 0.58,
                  t.get("grip", "#15161a"), "Fabric")
            b.cyl("GripRing", (sx * (GRIP_X + 0.75), BAR_Y, BAR_Z), 0.14, 0.66, glow, "Neon")
            b.cyl("GripRing", (sx * (GRIP_X - 0.75), BAR_Y, BAR_Z), 0.14, 0.66, glow, "Neon")


# --------------------------------------------------------------------------
# Tier 1 - Basic (dark steel + cyan neon, like the starter treadmill)
# --------------------------------------------------------------------------

def basic():
    b = Builder("Basic", seed=1)
    t = dict(dark="#2a2e36", light="#a7aeb8", trim="#4a505a", glow="#3fd8ff",
             base="#24272e", light_mat="Metal")
    frame(b, t)
    with b.in_group("Decor"):
        # console on the header with a pixel "up arrow", like the treadmill screen
        b.box("Console", (0, HEADER_TOP + 0.9, 0.1), (3.2, 1.6, 0.5), "#1a1d22", "Metal")
        b.box("Screen", (0, HEADER_TOP + 0.9, -0.17), (2.8, 1.25, 0.05), "#0b1a24", "Glass")
        arrow = [(0, 2), (-1, 1), (1, 1), (-2, 0), (2, 0), (0, 1), (0, 0), (0, -1)]
        for gx, gy in arrow:
            b.neon("Pixel", (gx * 0.2, HEADER_TOP + 0.85 + gy * 0.2, -0.21), (0.15, 0.15, 0.04),
                   "#bff3ff")
        for gx in (-5, -4, 4, 5):
            b.neon("Pixel", (gx * 0.22, HEADER_TOP + 0.5, -0.21), (0.15, 0.15, 0.04), "#3fd8ff")
        # chunky side handles like the treadmill arm rests
        for sx in (-1, 1):
            b.box("SideHandle", (sx * 5.2, 6.8, -0.9), (0.5, 0.5, 2.2), "#2a2e36", "Metal")
            b.neon("SideHandleGlow", (sx * 5.2, 6.8, -2.03), (0.32, 0.32, 0.06), "#3fd8ff")
    fx(b, "GlowLight", (0, 6, -1), (1, 1, 1), None, light("#3fd8ff", 1.2, 12))
    return b


# --------------------------------------------------------------------------
# Tier 2 - Inferno (red frame, lava floor, horns, flame tips, wheels)
# --------------------------------------------------------------------------

def inferno():
    b = Builder("Inferno", seed=2)
    t = dict(dark="#3a0a0a", light="#8b1010", trim="#c41e1e", glow="#ff6a00",
             base="#2a0606", mat="#3a0d05", bar="#ffb000", bar_mat="Neon", grip="#2a0606",
             frame_mat="SmoothPlastic", trim_mat="SmoothPlastic")
    frame(b, t)
    with b.in_group("Decor"):
        # lava floor with chevrons
        b.neon("Lava", (0, BASE_Y + 0.13, -0.6), (6.0, 0.06, 4.6), "#ff4a00")
        for i in range(5):
            z = -2.6 + i * 1.0
            for sx in (-1, 1):
                b.neon("Chevron", (sx * 1.0, BASE_Y + 0.18, z), (2.4, 0.06, 0.32), "#ffd000",
                       rot=(0, -sx * 28, 0))
        # wheels on the sides
        for sx in (-1, 1):
            for sz in (-1, 1):
                ring(b, "Wheel", (sx * 5.62, 0.9, sz * 2.0), 0.62, 0.22, 0.2, 10, "#ff7a00",
                     rot=(0, 90, 0))
                b.cyl("Hub", (sx * 5.62, 0.9, sz * 2.0), 0.18, 0.4, "#ffd000", "Neon")
        # flame emblem on the header
        b.neon("Emblem", (0, HEADER_Y, -0.76), (0.7, 0.7, 0.06), "#ffd000", rot=(0, 0, 45))
        b.neon("Emblem", (0, HEADER_Y + 0.5, -0.76), (0.3, 0.5, 0.06), "#ff7a00")
        # horns rising off the header ends
        for sx in (-1, 1):
            p = (sx * 5.0, HEADER_TOP + 0.2, 0)
            pts = [p, (sx * 5.35, HEADER_TOP + 1.2, 0), (sx * 5.55, HEADER_TOP + 2.2, 0),
                   (sx * 5.5, HEADER_TOP + 3.0, 0)]
            w = 0.75
            for a, c in zip(pts, pts[1:]):
                b.rod("Horn", a, c, w, "#8b1010", "SmoothPlastic")
                w *= 0.8
            b.neon("HornTip", (sx * 5.5, HEADER_TOP + 3.35, 0), (0.35, 0.5, 0.35), "#ffd000")
            fx(b, "HornFire", (sx * 5.5, HEADER_TOP + 3.5, 0), (0.4, 0.2, 0.4),
               flame("#ffd000", "#ff3a00", rate=20, size=0.9), light("#ff7a00", 2, 10))
            # inner horns (shorter)
            q = (sx * 3.6, HEADER_TOP + 0.2, 0)
            b.rod("Horn", q, (sx * 3.8, HEADER_TOP + 1.3, 0), 0.5, "#8b1010")
            b.neon("HornTip", (sx * 3.82, HEADER_TOP + 1.55, 0), (0.28, 0.35, 0.28), "#ffd000")
            # glowing side lamps
            b.neon("Lamp", (sx * 5.0, BAR_Y + 0.9, -0.55), (0.4, 0.4, 0.2), "#ffd000")
    fx(b, "Embers", (0, BASE_Y + 0.3, -0.6), (5.5, 0.2, 4.0), embers("#ffd000", "#ff3a00", 22),
       light("#ff5a00", 2.5, 16))
    for sx in (-1, 1):
        fx(b, "FootFire", (sx * 4.5, BASE_Y + 0.6, -3.4), (0.6, 0.2, 0.3),
           flame("#ffd000", "#ff3a00", rate=10, size=0.6))
    return b


# --------------------------------------------------------------------------
# Tier 3 - Celestial (white marble + gold, star sigil, wings, clouds, halos)
# --------------------------------------------------------------------------

def celestial():
    b = Builder("Celestial", seed=3)
    t = dict(dark="#e9edf3", light="#ffffff", trim="#d6a82c", glow="#7fd8ff",
             base="#f2f4f8", mat="#13204a", bar="#e2b33a", bar_mat="Foil", grip="#13204a",
             frame_mat="Marble", light_mat="Marble", trim_mat="Foil", base_mat="Marble")
    frame(b, t)
    with b.in_group("Decor"):
        # navy panel on the header with a gold edge
        b.box("Panel", (0, HEADER_Y, -0.6), (6.0, 0.9, 0.3), "#13204a", "SmoothPlastic")
        # gold oval crest with a glowing 4-point star (the treadmill's sigil)
        cy = HEADER_TOP + 2.8
        b.box("CrestStem", (0, HEADER_TOP + 0.5, 0), (1.2, 1.0, 0.8), "#d6a82c", "Foil")
        b.part("CrestFill", (0, cy, 0.05), (2.8, 3.8, 0.3), "#13204a", "SmoothPlastic",
               shape="Block")
        ring(b, "CrestRing", (0, cy, 0), 1.7, 0.42, 0.6, 22, "#d6a82c", mat="Foil", rx=1.7,
             ry=2.3)
        ring(b, "CrestGlow", (0, cy, -0.12), 1.4, 0.12, 0.5, 22, "#bff0ff", rx=1.42, ry=2.0)
        # 4-point star: tapered spikes around a bright core
        b.neon("Star", (0, cy, -0.3), (0.8, 0.8, 0.1), "#e6fbff", rot=(0, 0, 45),
               light=light("#7fd8ff", 2.5, 14))
        for ang, reach in ((90, 1.45), (270, 1.45), (0, 1.05), (180, 1.05)):
            with b.at((0, cy, -0.25), (0, 0, ang)):
                steps = [(0.42, 0.34), (0.3, 0.34), (0.18, 0.34), (0.08, 0.3)]
                x = 0.3
                for w, ln in steps:
                    ln = ln * reach / 1.2
                    b.neon("Star", (x + ln / 2, 0, 0), (ln, w, 0.1), "#5fd0ff")
                    x += ln
        # wings sweeping out of the crest
        for sx in (-1, 1):
            wing(b, "Wing", (sx * 1.3, cy - 0.2, 0.35), sx, "#ffffff", "#d6a82c")
        # gold banner tabs on the posts
        for sx in (-1, 1):
            b.box("Banner", (sx * 4.5, 7.3, -0.55), (0.8, 1.6, 0.1), "#13204a")
            b.box("BannerTrim", (sx * 4.5, 8.15, -0.56), (0.9, 0.15, 0.12), "#d6a82c", "Foil")
            b.neon("BannerMark", (sx * 4.5, 7.35, -0.62), (0.3, 0.3, 0.04), "#7fd8ff",
                   rot=(0, 0, 45))
        # clouds hugging the feet
        for sx in (-1, 1):
            for sz in (-1, 1):
                cloud(b, "Cloud", (sx * 5.4, 0.7, sz * 3.2), 1.15)
            cloud(b, "Cloud", (sx * 5.9, 0.6, 0), 0.9)
        cloud(b, "Cloud", (0, 0.5, 3.9), 1.0)
        # floating halos
        for (x, y, z, rx, rz, r) in [(-5.6, 13.6, -0.4, 70, 10, 0.75), (5.8, 12.8, 0.6, 60, -20, 0.7),
                                     (3.4, 15.4, -0.2, 75, 25, 0.6), (-3.0, 15.8, 0.3, 65, -15, 0.55)]:
            ring(b, "Halo", (x, y, z), r, 0.14, 0.14, 12, "#fff6d0", rot=(rx, 0, rz))
    fx(b, "Sparkles", (0, 9, 0), (9, 6, 2), sparkles("#ffffff", "#9fe6ff", rate=10))
    fx(b, "HolyLight", (0, 4, -1.5), (1, 1, 1), None, light("#cfefff", 1.5, 14))
    return b


# --------------------------------------------------------------------------
# Tier 4 - Void (obsidian, purple veins, galaxy portal, orbit rings, rubble)
# --------------------------------------------------------------------------

def void():
    b = Builder("Void", seed=4)
    glow = "#b45cff"
    t = dict(dark="#150c22", light="#22123a", trim="#2c1a46", glow=glow, base="#120a1c",
             mat="#1a0f2a", bar="#3a2266", grip="#0e0816", frame_mat="Slate",
             light_mat="Slate", trim_mat="Slate", base_mat="Slate")
    frame(b, t)
    with b.in_group("Decor"):
        # veins on the posts
        for sx in (-1, 1):
            specks(b, "Vein", glow, (sx * 4.5 - 0.55, 1.0, -0.56), (sx * 4.5 + 0.55, 10.4, 0.56), 22)
        # tall broken chimney on the left (the treadmill's asymmetric pillar)
        b.box("Chimney", (-4.5, HEADER_TOP + 1.5, 0.2), (1.3, 3.0, 1.3), "#150c22", "Slate")
        b.box("Chimney", (-4.4, HEADER_TOP + 3.5, 0.2), (1.0, 1.0, 1.0), "#22123a", "Slate")
        b.neon("ChimneyGlow", (-4.5, HEADER_TOP + 1.8, -0.47), (0.2, 2.2, 0.06), glow)
        # portal ring of dark stone with a galaxy swirl
        pc = (0.4, HEADER_TOP + 2.9, 0.2)
        b.box("PortalStem", (0.4, HEADER_TOP + 0.4, 0.2), (1.6, 0.8, 1.0), "#150c22", "Slate")
        ring(b, "Portal", pc, 2.2, 0.75, 0.9, 20, "#1c1030", mat="Slate")
        b.disc("PortalCore", (pc[0], pc[1], pc[2] + 0.15), 3.8, 0.2, "#05020a", "SmoothPlastic")
        for arm in range(3):
            for i in range(16):
                tt = i / 15
                a = arm * 2 * math.pi / 3 + tt * 2.6 * math.pi
                r = 0.15 + tt * 1.6
                s = 0.16 + 0.12 * tt
                b.neon("Swirl", (pc[0] + r * math.cos(a), pc[1] + r * math.sin(a), pc[2] - 0.02),
                       (s, s, 0.08), mix("#ffffff", glow, min(1, tt * 1.6)))
        b.neon("PortalEye", (pc[0], pc[1], pc[2] - 0.05), (0.4, 0.4, 0.08), "#ffffff",
               light=light(glow, 3, 16))
        # orbit rings
        ring(b, "Orbit", (pc[0], pc[1], pc[2]), 3.0, 0.14, 0.14, 26, glow, rot=(72, 0, 18))
        ring(b, "Orbit", (4.6, HEADER_TOP + 1.6, 0), 0.9, 0.14, 0.14, 12, glow, rot=(80, 0, -15))
        ring(b, "Orbit", (-4.5, HEADER_TOP + 4.6, 0.2), 0.7, 0.12, 0.12, 10, glow, rot=(75, 0, 10))
        # floating crystals
        for p in [(-6.2, 6.5, -1.5), (6.3, 7.4, -0.5), (-6.0, 11.0, 0.8), (6.0, 12.2, 1.0),
                  (-2.6, 16.6, 0), (3.2, 16.2, 0.4), (6.8, 3.4, 1.8), (-6.8, 3.0, 2.2)]:
            gem(b, "Shard", p, 0.75, "#e2b8ff", spin=b.rng.uniform(-30, 30))
        rubble(b, "Rubble", ["#120a1c", "#1d1030", "#26173d"], glow, 130)
    fx(b, "VoidSparkles", (0, 7, 0), (11, 9, 5), sparkles("#e2b8ff", glow, rate=14))
    fx(b, "VoidLight", (0, 3, -1.5), (1, 1, 1), None, light(glow, 1.8, 14))
    return b


# --------------------------------------------------------------------------
# Tier 5 - Frostbite (ice spikes, horned skull, chains, frost cracks)
# --------------------------------------------------------------------------

def frostbite():
    b = Builder("Frostbite", seed=5)
    glow = "#5fe8ff"
    t = dict(dark="#0f1b2c", light="#16283f", trim="#cfd6df", glow=glow, base="#0d1726",
             mat="#0d1a28", bar="#dff6ff", bar_mat="Ice", grip="#0d1726", frame_mat="Slate",
             light_mat="Slate", trim_mat="Metal", base_mat="Slate")
    frame(b, t)
    with b.in_group("Decor"):
        for sx in (-1, 1):
            specks(b, "Crack", glow, (sx * 4.5 - 0.55, 1.0, -0.56), (sx * 4.5 + 0.55, 10.4, 0.56), 20)
        # pedestal + horned skull on top
        b.box("Pedestal", (0, HEADER_TOP + 0.9, 0.1), (2.4, 1.8, 1.8), "#0f1b2c", "Slate")
        b.neon("PedestalGlow", (0, HEADER_TOP + 0.9, -0.82), (1.4, 1.0, 0.06), glow)
        b.neon("PedestalGlow", (0, HEADER_TOP + 0.9, -0.84), (0.3, 1.4, 0.06), "#e8fdff")
        skull(b, "Skull", (0, HEADER_TOP + 3.1, 0.1), "#c9ced8", glow, "#e9edf3", glow, 1.0)
        # chains from the header down to the back corners
        for sx in (-1, 1):
            chain(b, "Chain", (sx * 5.0, HEADER_Y, 0.6), (sx * 5.3, BASE_Y + 0.3, 3.3), "#b8c1cc",
                  sag=0.6)
            chain(b, "Chain", (sx * 1.6, HEADER_Y - 0.6, 0.6), (sx * 3.0, BASE_Y + 0.3, 3.4),
                  "#b8c1cc", sag=0.5)
        # ice spikes clustered around the feet
        spots = [(-5.9, -3.4, 2.2, (-14, 0, 12)), (-6.3, -1.8, 1.6, (0, 0, 20)),
                 (-6.0, 1.2, 2.6, (8, 0, 15)), (-5.6, 3.6, 2.0, (14, 0, 6)),
                 (5.9, -3.4, 2.4, (-12, 0, -14)), (6.4, -1.4, 1.5, (0, 0, -22)),
                 (6.1, 1.6, 2.8, (8, 0, -12)), (5.4, 3.8, 1.8, (12, 0, -8)),
                 (-3.4, 4.0, 1.7, (18, 0, 0)), (3.0, 4.1, 2.1, (16, 0, 0)),
                 (0.0, 4.2, 1.4, (20, 0, 0)), (-4.6, 2.6, 1.3, (10, 0, 10)),
                 (4.6, 2.6, 1.2, (10, 0, -10))]
        for x, z, h, tilt in spots:
            crystal(b, "IceSpike", (x, 0.2, z), h, 0.6, "#bff4ff", tilt=tilt, glow_color=glow)
            crystal(b, "IceSpike", (x + 0.5, 0.1, z + 0.3), h * 0.6, 0.4, "#9fe9ff",
                    tilt=(tilt[0], 0, tilt[2] * 1.5), glow_color=None)
        # ice on the header ends
        for sx in (-1, 1):
            crystal(b, "IceSpike", (sx * 5.0, HEADER_TOP, 0), 1.4, 0.5, "#bff4ff",
                    tilt=(0, 0, -sx * 18), glow_color=glow)
        for p in [(-6.6, 8.0, -0.5), (6.6, 9.0, 0.3), (-2.8, 15.6, 0.4), (3.0, 15.2, -0.2),
                  (-6.2, 12.6, 0.8), (6.0, 13.2, 1.0)]:
            gem(b, "FrostShard", p, 0.6, "#d8fbff", spin=b.rng.uniform(-30, 30))
        rubble(b, "Rubble", ["#0d1726", "#12223a", "#1a2c48"], glow, 110, speck_rate=0.3)
    fx(b, "Snow", (0, 13, 0), (12, 1, 6), snow("#bff4ff", rate=14))
    fx(b, "FrostLight", (0, 4, -1.2), (1, 1, 1), None, light(glow, 1.8, 14))
    fx(b, "SkullGlow", (0, HEADER_TOP + 3.0, -1.2), (0.5, 0.5, 0.5),
       sparkles(glow, "#ffffff", rate=6, size=0.25), light(glow, 2, 8))
    return b


# --------------------------------------------------------------------------
# Tier 6 - Storm Citadel (castle towers, gold spires, lightning orb)
# --------------------------------------------------------------------------

def stormcastle():
    b = Builder("Stormcastle", seed=6)
    glow = "#3aa8ff"
    gold = "#e0b040"
    t = dict(dark="#0c1430", light="#121c40", trim=gold, glow=glow, base="#0a1028",
             mat="#0c1430", bar=gold, bar_mat="Foil", grip="#0a1028", frame_mat="Slate",
             light_mat="Slate", trim_mat="Foil", base_mat="Slate", post_w=1.4)
    frame(b, t)
    with b.in_group("Decor"):
        for sx in (-1, 1):
            x = sx * 4.5
            specks(b, "Window", glow, (x - 0.75, 1.0, -0.76), (x + 0.75, 10.4, 0.76), 18)
            # crenellated tower top with gold spire
            b.box("TowerTop", (x, HEADER_TOP + 0.5, 0), (1.9, 1.0, 1.9), "#0c1430", "Slate")
            for cx, cz in [(-0.7, -0.7), (0.7, -0.7), (-0.7, 0.7), (0.7, 0.7)]:
                b.box("Merlon", (x + cx, HEADER_TOP + 1.25, cz), (0.45, 0.5, 0.45), "#0c1430",
                      "Slate")
            spire(b, "Spire", (x, HEADER_TOP + 1.0, 0), 1.2, 3.2, gold, "#fff1b0", mat="Foil")
            # small back turrets
            b.box("Turret", (sx * 5.4, 3.2, 2.6), (1.4, 5.2, 1.4), "#0c1430", "Slate")
            specks(b, "Window", glow, (sx * 5.4 - 0.72, 1.2, 1.88), (sx * 5.4 + 0.72, 5.6, 3.32), 8)
            spire(b, "Spire", (sx * 5.4, 5.8, 2.6), 1.0, 2.4, gold, "#fff1b0", mat="Foil")
        # crest panel with a lightning bolt
        b.box("Crest", (0, HEADER_TOP + 1.5, 0.2), (3.6, 3.0, 0.8), "#0c1430", "Slate")
        b.box("CrestTrim", (0, HEADER_TOP + 3.05, 0.2), (3.9, 0.25, 1.0), gold, "Foil")
        for sx in (-1, 1):
            b.box("CrestTrim", (sx * 1.85, HEADER_TOP + 1.5, 0.2), (0.25, 3.0, 1.0), gold, "Foil")
        bolt(b, "Bolt", (0, HEADER_TOP + 1.5, -0.25), 1.15, "#8fd8ff")
        # glowing orb with gold sun rays
        oc = (0, HEADER_TOP + 4.6, 0.2)
        b.ball("Orb", oc, 2.3, "#6fd0ff", "Neon", light=light(glow, 3.5, 20))
        ring(b, "OrbRing", oc, 1.45, 0.3, 0.5, 18, gold, mat="Foil")
        for i in range(12):
            a = 2 * math.pi * i / 12
            r0, r1 = 1.65, 2.35 if i % 2 == 0 else 2.0
            b.rod("Ray", (oc[0] + r0 * math.cos(a), oc[1] + r0 * math.sin(a), oc[2] + 0.1),
                  (oc[0] + r1 * math.cos(a), oc[1] + r1 * math.sin(a), oc[2] + 0.1), 0.22, gold,
                  "Foil")
        # floating debris cubes
        for p in [(-6.4, 12.4, 0.6), (6.6, 13.2, -0.4), (-3.4, 16.8, 0.5), (3.8, 17.0, -0.3),
                  (-7.0, 7.0, 1.4), (7.1, 8.2, 1.2), (-2.2, 14.8, -1.2)]:
            s = b.rng.uniform(0.4, 0.75)
            b.box("Debris", p, (s, s, s), "#1b2238", "Slate",
                  rot=(b.rng.uniform(0, 45), b.rng.uniform(0, 45), b.rng.uniform(0, 45)))
        rubble(b, "Rubble", ["#0a1028", "#101a3a", "#16224a"], glow, 120)
    fx(b, "Sparks", oc, (1.5, 1.5, 1.5), sparks("#9fe0ff", rate=10))
    fx(b, "StormLight", (0, 4, -1.2), (1, 1, 1), None, light(glow, 1.8, 14))
    fx(b, "BoltSparks", (0, HEADER_TOP + 1.5, -0.6), (1.5, 2.5, 0.3),
       sparkles("#9fe0ff", "#ffffff", rate=6, size=0.3))
    return b


# --------------------------------------------------------------------------
# Tier 7 - Arcane (magenta, peacock fans, crown, X sigil, chains)
# --------------------------------------------------------------------------

def arcane():
    b = Builder("Arcane", seed=7)
    glow = "#ff4fd8"
    t = dict(dark="#1a0b24", light="#2a1238", trim="#3d1a52", glow=glow, base="#150920",
             mat="#1e0d2a", bar="#ff8ae8", bar_mat="Neon", grip="#150920", frame_mat="Slate",
             light_mat="Slate", trim_mat="Slate", base_mat="Slate")
    frame(b, t)
    with b.in_group("Decor"):
        for sx in (-1, 1):
            specks(b, "Rune", glow, (sx * 4.5 - 0.55, 1.0, -0.56), (sx * 4.5 + 0.55, 10.4, 0.56), 20)
        # tower crest with the X sigil
        b.box("Tower", (0, HEADER_TOP + 1.6, 0.2), (3.0, 3.2, 1.2), "#1a0b24", "Slate")
        x_panel(b, "Sigil", (0, HEADER_TOP + 1.6, -0.45), 2.4, 2.6, "#13081c", glow)
        b.box("TowerCap", (0, HEADER_TOP + 3.35, 0.2), (3.3, 0.3, 1.5), "#3d1a52", "Slate")
        crown(b, "Crown", (0, HEADER_TOP + 3.75, 0.2), "#f2e6ff", glow, 1.0)
        fx(b, "CrownFlame", (0, HEADER_TOP + 4.4, 0.2), (0.8, 0.2, 0.8),
           flame("#ffffff", glow, rate=16, size=0.7), light(glow, 2.5, 12))
        # peacock fans either side of the tower
        for sx in (-1, 1):
            fan(b, "Fan", (sx * 1.9, HEADER_TOP + 2.6, 0.5), sx, "#ff6ae0", "#ffd6f6",
                feathers=9, length=3.0, spread=(5, 120), layers=2)
        # chains from the tower to the back of the base
        for sx in (-1, 1):
            chain(b, "Chain", (sx * 1.4, HEADER_TOP + 0.6, 0.8), (sx * 4.8, BASE_Y + 0.3, 3.3),
                  "#4a3a58", sag=0.8)
        for p in [(-6.4, 7.2, -0.8), (6.5, 8.4, 0.2), (-5.8, 12.6, 0.6), (5.6, 13.2, 1.0),
                  (-2.6, 17.4, 0.4), (2.8, 17.0, -0.2), (-7.0, 3.4, 2.0), (7.0, 4.0, 2.2)]:
            gem(b, "Gem", p, 0.7, "#ff9ef0", spin=b.rng.uniform(-30, 30))
        rubble(b, "Rubble", ["#150920", "#211033", "#2b1640"], glow, 120)
        # little bone-white flowers in the rubble like the treadmill
        for i in range(6):
            x = b.rng.choice([-1, 1]) * b.rng.uniform(5.6, 6.8)
            z = b.rng.uniform(-3.5, 4.5)
            for k in range(4):
                a = k * 90 + 45
                b.box("Petal", (x + 0.18 * math.cos(math.radians(a)), 1.1, z + 0.18 * math.sin(math.radians(a))),
                      (0.28, 0.1, 0.28), "#ffe6fb", rot=(0, a, 0))
    fx(b, "ArcaneSparkles", (0, 8, 0), (11, 9, 5), sparkles("#ffd6f6", glow, rate=12))
    fx(b, "ArcaneLight", (0, 4, -1.2), (1, 1, 1), None, light(glow, 1.8, 14))
    return b


# --------------------------------------------------------------------------
# Tier 8 - Blood Moon (huge red moon, gothic spikes, chains, bones)
# --------------------------------------------------------------------------

def bloodmoon():
    b = Builder("BloodMoon", seed=8)
    glow = "#ff2a2a"
    t = dict(dark="#1a0606", light="#2a0a0a", trim="#3a0c0c", glow=glow, base="#140404",
             mat="#200606", bar="#ff3b30", bar_mat="Neon", grip="#140404", frame_mat="Slate",
             light_mat="Slate", trim_mat="Slate", base_mat="Slate")
    frame(b, t)
    with b.in_group("Decor"):
        for sx in (-1, 1):
            specks(b, "Vein", glow, (sx * 4.5 - 0.55, 1.0, -0.56), (sx * 4.5 + 0.55, 10.4, 0.56), 22)
            spire(b, "Spire", (sx * 4.5, HEADER_TOP + 0.2, 0), 1.2, 2.8, "#1a0606", glow,
                  mat="Slate")
        # the moon
        mc = (0, HEADER_TOP + 4.0, 1.2)
        b.disc("Moon", mc, 7.4, 0.6, "#ff3b30", "Neon", light=light(glow, 4, 24))
        for (cx, cy, d) in [(-1.6, 1.4, 1.5), (1.4, 0.6, 1.1), (-0.4, -1.6, 1.8), (1.9, -1.5, 0.8),
                            (-2.3, -0.4, 0.9), (0.4, 2.4, 0.7), (0.0, 0.2, 0.6), (2.6, 1.6, 0.5)]:
            b.disc("Crater", (mc[0] + cx, mc[1] + cy, mc[2] - 0.32), d, 0.08, "#a8121a",
                   "SmoothPlastic")
        ring(b, "MoonRim", mc, 3.75, 0.3, 0.7, 28, "#1a0606", mat="Slate")
        for i in range(10):
            a = 2 * math.pi * i / 10 + math.pi / 10
            r0, r1 = 3.7, 4.7
            b.rod("Spike", (mc[0] + r0 * math.cos(a), mc[1] + r0 * math.sin(a), mc[2]),
                  (mc[0] + r1 * math.cos(a), mc[1] + r1 * math.sin(a), mc[2]), 0.35, "#1a0606",
                  "Slate")
        # gothic arch in front of the moon
        b.box("Arch", (0, HEADER_TOP + 1.2, 0.1), (3.0, 2.4, 1.0), "#1a0606", "Slate")
        b.neon("ArchGlow", (0, HEADER_TOP + 1.1, -0.42), (1.6, 1.6, 0.06), "#ff5a4a",
               rot=(0, 0, 45))
        b.box("ArchInner", (0, HEADER_TOP + 1.1, -0.44), (1.0, 1.0, 0.06), "#1a0606",
              rot=(0, 0, 45))
        for sx in (-1, 1):
            spire(b, "Spire", (sx * 1.3, HEADER_TOP + 2.4, 0.1), 0.6, 1.6, "#1a0606", glow,
                  mat="Slate", layers=3)
        # chains
        for sx in (-1, 1):
            chain(b, "Chain", (sx * 1.5, HEADER_TOP + 0.5, 0.7), (sx * 5.0, BASE_Y + 0.3, 3.4),
                  "#2a1a1a", sag=0.9)
            chain(b, "Chain", (sx * 5.0, HEADER_Y, -0.8), (sx * 3.4, BAR_Y - 2.0, -0.8),
                  "#2a1a1a", sag=0.3)
        # bones and skulls
        for (x, z, ry) in [(-6.0, -2.8, 30), (6.2, -2.4, -20), (-5.8, 3.0, 70), (5.6, 3.6, 10),
                           (2.2, 4.4, 45), (-2.4, 4.6, -35)]:
            bone(b, "Bone", (x, 0.9, z), 1.1, ry)
        for (x, z, ry) in [(-6.4, 0.6, 20), (6.5, 1.2, -25), (0.6, 4.6, 180), (-4.0, -4.2, 10)]:
            mini_skull(b, "Skull", (x, 1.05, z), ry)
        rubble(b, "Rubble", ["#140404", "#200808", "#2c0c0c"], glow, 130)
    fx(b, "Drips", (0, HEADER_TOP + 1.0, -0.6), (9, 0.2, 0.4), drips("#ff2a2a", rate=6))
    fx(b, "Embers", (0, 7, 1), (11, 8, 4), sparkles("#ff6a5a", glow, rate=8, size=0.3))
    fx(b, "MoonLight", (0, 4, -1.2), (1, 1, 1), None, light(glow, 1.8, 14))
    return b


# --------------------------------------------------------------------------
# Tier 9 - Toxic (emerald gothic spires, X sigil, chains, floating gems)
# --------------------------------------------------------------------------

def toxic():
    b = Builder("Toxic", seed=9)
    glow = "#2dff9a"
    t = dict(dark="#06180f", light="#0a2416", trim="#0f3320", glow=glow, base="#041209",
             mat="#082014", bar="#5affb4", bar_mat="Neon", grip="#041209", frame_mat="Slate",
             light_mat="Slate", trim_mat="Slate", base_mat="Slate")
    frame(b, t)
    with b.in_group("Decor"):
        for sx in (-1, 1):
            specks(b, "Vein", glow, (sx * 4.5 - 0.55, 1.0, -0.56), (sx * 4.5 + 0.55, 10.4, 0.56), 22)
            spire(b, "Spire", (sx * 4.5, HEADER_TOP + 0.2, 0), 1.3, 3.6, "#06180f", glow,
                  mat="Slate", layers=5)
            gem(b, "Gem", (sx * 4.5, HEADER_TOP + 5.0, 0), 0.9, "#7dffc4",
                light=light(glow, 1.5, 8))
            # small side spires
            spire(b, "Spire", (sx * 5.6, BASE_Y, 2.8), 0.9, 4.2, "#06180f", glow, mat="Slate")
            gem(b, "Gem", (sx * 5.6, BASE_Y + 5.2, 2.8), 0.6, "#7dffc4")
        # X sigil crest
        b.box("Crest", (0, HEADER_TOP + 1.5, 0.2), (3.4, 3.0, 1.0), "#06180f", "Slate")
        x_panel(b, "Sigil", (0, HEADER_TOP + 1.5, -0.35), 2.8, 2.4, "#041209", glow)
        b.box("CrestCap", (0, HEADER_TOP + 3.15, 0.2), (3.7, 0.3, 1.3), "#0f3320", "Slate")
        for sx in (-1, 1):
            spire(b, "Spire", (sx * 1.5, HEADER_TOP + 3.3, 0.2), 0.6, 1.6, "#06180f", glow,
                  mat="Slate", layers=3)
        # chains draped over the crest
        for sx in (-1, 1):
            chain(b, "Chain", (sx * 1.6, HEADER_TOP + 2.8, 0.6), (sx * 4.9, BASE_Y + 0.3, 3.2),
                  "#1d3a2a", sag=1.0)
        for p in [(-6.6, 7.0, -0.6), (6.6, 8.0, 0.2), (-6.0, 12.8, 0.8), (6.2, 12.4, 1.0),
                  (-2.0, 17.0, 0.2), (2.2, 16.6, -0.2), (-7.2, 3.6, 1.6), (7.2, 3.8, 1.8)]:
            gem(b, "Gem", p, 0.7, "#7dffc4", spin=b.rng.uniform(-30, 30))
        rubble(b, "Rubble", ["#041209", "#082014", "#0c2c1b"], glow, 130)
    fx(b, "ToxicBubbles", (0, BASE_Y + 0.4, 0), (11, 0.4, 6), bubbles(glow, rate=14))
    fx(b, "ToxicLight", (0, 4, -1.2), (1, 1, 1), None, light(glow, 1.8, 14))
    return b


TIERS = [
    (1, "Basic", basic, "#2f4f7a"),
    (2, "Inferno", inferno, "#7a1d14"),
    (3, "Celestial", celestial, "#2f5f8f"),
    (4, "Void", void, "#3a2470"),
    (5, "Frostbite", frostbite, "#24486f"),
    (6, "Stormcastle", stormcastle, "#1d2f6a"),
    (7, "Arcane", arcane, "#4a2470"),
    (8, "Blood Moon", bloodmoon, "#6e1a1a"),
    (9, "Toxic", toxic, "#1d5a3a"),
]
