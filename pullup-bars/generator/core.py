"""Part builder and voxel-style shape helpers.

Everything is built in Roblox studs, Y-up, with the model origin on the ground
at the centre of the pull-up bar. The grip bar runs along X, the front of the
station (where the player hangs) faces -Z, which is Roblox's default
LookVector.
"""
from __future__ import annotations

import math
import random
from contextlib import contextmanager

import numpy as np

# --------------------------------------------------------------------------
# Rotation helpers
# --------------------------------------------------------------------------

I3 = np.eye(3)


def _rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def _ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def _rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def angles(rx=0.0, ry=0.0, rz=0.0):
    """Same as Roblox CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))."""
    return _rx(math.radians(rx)) @ _ry(math.radians(ry)) @ _rz(math.radians(rz))


def as_rot(r):
    if r is None:
        return I3
    if isinstance(r, np.ndarray):
        return r
    return angles(*r)


def look_along(direction, roll=0.0):
    """Rotation whose local +X axis points along `direction` (used for
    cylinders and chain links). `roll` spins it around that axis (degrees)."""
    x = np.asarray(direction, float)
    x = x / np.linalg.norm(x)
    up = np.array([0.0, 1.0, 0.0])
    if abs(np.dot(x, up)) > 0.98:
        up = np.array([0.0, 0.0, 1.0])
    z = np.cross(x, up)
    z /= np.linalg.norm(z)
    y = np.cross(z, x)
    m = np.column_stack([x, y, z])
    return m @ angles(roll, 0, 0)


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    ra, rb = hex_rgb(a), hex_rgb(b)
    return "#%02x%02x%02x" % tuple(round(ra[i] + (rb[i] - ra[i]) * t) for i in range(3))


# --------------------------------------------------------------------------
# Builder
# --------------------------------------------------------------------------

class Builder:
    def __init__(self, name, seed=1):
        self.name = name
        self.parts = []
        self.rng = random.Random(seed)
        self._stack = [(I3, np.zeros(3))]
        self.group = "Frame"

    # -- transforms ---------------------------------------------------------
    @contextmanager
    def at(self, pos=(0, 0, 0), rot=None):
        R0, p0 = self._stack[-1]
        R = R0 @ as_rot(rot)
        p = p0 + R0 @ np.asarray(pos, float)
        self._stack.append((R, p))
        try:
            yield
        finally:
            self._stack.pop()

    @contextmanager
    def in_group(self, group):
        old = self.group
        self.group = group
        try:
            yield
        finally:
            self.group = old

    def world(self, pos=(0, 0, 0)):
        R0, p0 = self._stack[-1]
        return p0 + R0 @ np.asarray(pos, float)

    # -- the one primitive --------------------------------------------------
    def part(self, name, pos, size, color, mat="SmoothPlastic", rot=None,
             shape="Block", transparency=0.0, collide=False, shadow=True,
             reflectance=0.0, light=None, emitter=None, attachments=None):
        R0, p0 = self._stack[-1]
        R = R0 @ as_rot(rot)
        p = p0 + R0 @ np.asarray(pos, float)
        if shape == "Ball":
            d = min(size)
            size = (d, d, d)
        elif shape == "Cylinder":
            d = min(size[1], size[2])
            size = (size[0], d, d)
        rec = {
            "name": name,
            "group": self.group,
            "pos": [float(v) for v in p],
            "rot": [[float(v) for v in row] for row in R],
            "size": [float(v) for v in size],
            "color": color,
            "mat": mat,
            "shape": shape,
            "transparency": float(transparency),
            "collide": bool(collide),
            "shadow": bool(shadow) and mat != "Neon",
            "reflectance": float(reflectance),
        }
        if light:
            rec["light"] = light
        if emitter:
            rec["emitter"] = emitter
        if attachments:
            # attachments are given in world space of the current frame;
            # store them relative to this part.
            rec["attachments"] = [
                {"name": n, "pos": [float(v) for v in R.T @ (self.world(ap) - p)]}
                for n, ap in attachments
            ]
        self.parts.append(rec)
        return rec

    # convenience wrappers ---------------------------------------------------
    def box(self, name, pos, size, color, mat="SmoothPlastic", **kw):
        return self.part(name, pos, size, color, mat, **kw)

    def neon(self, name, pos, size, color, **kw):
        kw.setdefault("shadow", False)
        return self.part(name, pos, size, color, "Neon", **kw)

    def ball(self, name, pos, d, color, mat="SmoothPlastic", **kw):
        return self.part(name, pos, (d, d, d), color, mat, shape="Ball", **kw)

    def cyl(self, name, pos, length, d, color, mat="SmoothPlastic", rot=None, **kw):
        """Cylinder along local X (Roblox convention)."""
        return self.part(name, pos, (length, d, d), color, mat, rot=rot,
                         shape="Cylinder", **kw)

    def disc(self, name, pos, d, thick, color, mat="SmoothPlastic", **kw):
        """Flat disc facing -Z (cylinder whose axis runs along Z)."""
        return self.cyl(name, pos, thick, d, color, mat, rot=(0, 90, 0), **kw)

    def rod(self, name, a, b, thick, color, mat="SmoothPlastic", square=True, **kw):
        """Box/cylinder spanning two points."""
        a, b = np.asarray(a, float), np.asarray(b, float)
        mid = (a + b) / 2
        length = float(np.linalg.norm(b - a))
        R = look_along(b - a)
        if square:
            return self.part(name, mid, (length, thick, thick), color, mat, rot=R, **kw)
        return self.part(name, mid, (length, thick, thick), color, mat, rot=R,
                         shape="Cylinder", **kw)


# --------------------------------------------------------------------------
# Shape helpers (voxel style)
# --------------------------------------------------------------------------

def ring(b, name, center, radius, thick, depth, segs, color, mat="Neon", rot=None,
         rx=None, ry=None):
    """Ring of blocks lying in the local XY plane (faces -Z). Optional rx/ry
    make it an ellipse."""
    rx = rx or radius
    ry = ry or radius
    with b.at(center, rot):
        pts = [(rx * math.cos(2 * math.pi * i / segs), ry * math.sin(2 * math.pi * i / segs))
               for i in range(segs)]
        for i in range(segs):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % segs]
            mx, my = (x0 + x1) / 2, (y0 + y1) / 2
            ln = math.hypot(x1 - x0, y1 - y0) * 1.12
            ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
            if mat == "Neon":
                b.neon(name, (mx, my, 0), (ln, thick, depth), color, rot=(0, 0, ang))
            else:
                b.box(name, (mx, my, 0), (ln, thick, depth), color, mat, rot=(0, 0, ang))


def chain(b, name, p0, p1, color, sag=0.8, link=0.55, mat="Metal"):
    """Hanging chain from p0 to p1 made of alternating flat links."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    dist = np.linalg.norm(p1 - p0)
    n = max(3, int(dist / (link * 0.8)))

    def pt(t):
        q = p0 + (p1 - p0) * t
        q[1] -= sag * 4 * t * (1 - t)
        return q

    for i in range(n):
        t0, t1 = i / n, (i + 1) / n
        a, c = pt(t0), pt(t1)
        R = look_along(c - a, roll=90 if i % 2 else 0)
        b.part(name, (a + c) / 2, (np.linalg.norm(c - a) * 1.15, 0.32, 0.12), color, mat,
               rot=R)


def spire(b, name, base, width, height, color, tip_color, layers=4, mat="SmoothPlastic",
          tip_mat="Neon"):
    x, y, z = base
    h = height / (layers + 1)
    for i in range(layers):
        w = width * (1 - i / (layers + 0.6))
        b.box(name, (x, y + h * i + h / 2, z), (w, h, w), color, mat)
    tw = width * 0.22
    tip = (x, y + h * layers + h * 0.6, z)
    if tip_mat == "Neon":
        b.neon(name + "Tip", tip, (tw, h * 1.2, tw), tip_color)
    else:
        b.box(name + "Tip", tip, (tw, h * 1.2, tw), tip_color, tip_mat)


def gem(b, name, pos, size, color, mat="Neon", light=None, spin=0):
    """Floating diamond: a box spun 45 degrees plus a small cap."""
    with b.at(pos, (0, spin, 0)):
        b.part(name, (0, 0, 0), (size * 0.7, size * 0.7, size * 0.3), color, mat,
               rot=(0, 0, 45), shadow=False, light=light)
        b.part(name, (0, size * 0.62, 0), (size * 0.2, size * 0.35, size * 0.2), color, mat,
               shadow=False)


def crystal(b, name, base, height, width, color, tilt=(0, 0, 0), mat="Ice",
            transparency=0.15, glow_color=None):
    with b.at(base, tilt):
        b.part(name, (0, height * 0.35, 0), (width, height * 0.7, width), color, mat,
               rot=(0, 45, 0), transparency=transparency)
        b.part(name, (0, height * 0.78, 0), (width * 0.6, height * 0.3, width * 0.6), color,
               mat, rot=(0, 45, 0), transparency=transparency)
        b.part(name, (0, height * 0.97, 0), (width * 0.25, height * 0.14, width * 0.25),
               glow_color or color, "Neon" if glow_color else mat, rot=(0, 45, 0))


def rubble(b, name, colors, speck, count, inner=(5.4, 3.4), outer=(7.4, 5.2), height=1.6,
           speck_rate=0.35):
    """Pile of voxel rock around the footprint with glowing specks, like the
    rubble skirts on the higher-tier treadmills."""
    rng = b.rng
    placed = 0
    tries = 0
    while placed < count and tries < count * 40:
        tries += 1
        x = rng.uniform(-outer[0], outer[0])
        z = rng.uniform(-outer[1], outer[1])
        ex = (x / outer[0]) ** 2 + (z / outer[1]) ** 2
        if ex > 1:
            continue
        if abs(x) < inner[0] - 0.4 and abs(z) < inner[1] - 0.4:
            continue  # keep the standing area clear
        if abs(x) < 3.2 and z < -2.2:
            continue  # keep the front entry clear
        falloff = max(0.15, 1 - ex)
        s = rng.uniform(0.45, 1.05)
        y = rng.uniform(0, height * falloff)
        col = rng.choice(colors)
        b.box(name, (x, y + s / 2, z), (s, s, s), col, "Slate",
              rot=(0, rng.choice([0, 15, 30, 45]), 0))
        if rng.random() < speck_rate:
            ss = rng.uniform(0.14, 0.26)
            # sit the speck on one of the visible faces
            face = rng.choice(["top", "x", "z"])
            if face == "top":
                off = (rng.uniform(-s / 3, s / 3), s / 2 + 0.01, rng.uniform(-s / 3, s / 3))
            elif face == "x":
                off = (math.copysign(s / 2 + 0.01, x), rng.uniform(-s / 3, s / 3),
                       rng.uniform(-s / 3, s / 3))
            else:
                off = (rng.uniform(-s / 3, s / 3), rng.uniform(-s / 3, s / 3),
                       math.copysign(s / 2 + 0.01, z))
            b.neon(name + "Glow", (x + off[0], y + s / 2 + off[1], z + off[2]), (ss, ss, ss),
                   speck)
        placed += 1


def specks(b, name, color, region_min, region_max, count, size=(0.12, 0.22)):
    """Glowing specks scattered over a box region (cracks / veins)."""
    rng = b.rng
    for _ in range(count):
        p = [rng.uniform(region_min[i], region_max[i]) for i in range(3)]
        s = rng.uniform(*size)
        b.neon(name, p, (s, s * rng.choice([1, 2, 3]), s), color)


def cloud(b, name, pos, scale=1.0, color="#ffffff"):
    rng = b.rng
    offsets = [(0, 0, 0, 1.0), (0.7, -0.15, 0.2, 0.8), (-0.7, -0.15, -0.1, 0.8),
               (0.25, 0.4, -0.2, 0.75), (-0.3, 0.35, 0.3, 0.7), (0.0, -0.2, 0.6, 0.7),
               (0.1, -0.2, -0.6, 0.7)]
    with b.at(pos):
        for ox, oy, oz, s in offsets:
            j = rng.uniform(0.9, 1.1)
            b.ball(name, (ox * scale, oy * scale, oz * scale), 1.2 * s * scale * j, color,
                   "SmoothPlastic")


def fan(b, name, pos, side, color, tip, feathers=7, length=3.2, spread=(15, 165), rot=None,
        layers=2, mat="Neon", tip_mat="Neon"):
    """Feather fan (wings / peacock fans). Lies in the local XY plane."""
    with b.at(pos, rot):
        for layer in range(layers):
            L = length * (1 - layer * 0.28)
            z = layer * -0.18
            for k in range(feathers):
                t = k / (feathers - 1)
                a = spread[0] + (spread[1] - spread[0]) * t
                if side < 0:
                    a = 180 - a
                ar = math.radians(a)
                ln = L * (0.75 + 0.25 * math.sin(math.pi * t))
                cx, cy = math.cos(ar) * ln / 2, math.sin(ar) * ln / 2
                col = color if layer == 0 else mix(color, "#ffffff", 0.35)
                b.part(name, (cx, cy, z), (ln, 0.42, 0.2), col, mat, rot=(0, 0, a),
                       shadow=mat != "Neon")
                if layer == 0 and tip:
                    tx, ty = math.cos(ar) * ln, math.sin(ar) * ln
                    b.part(name + "Tip", (tx, ty, z - 0.05), (0.5, 0.5, 0.22), tip, tip_mat,
                           rot=(0, 0, 45), shadow=False)


def wing(b, name, pos, side, color, trim, rot=None):
    """Angel wing: stacked rows of feathers sweeping up and outwards."""
    with b.at(pos, rot):
        rows = [(0.0, 3.4, 60), (-0.45, 2.8, 40), (-0.9, 2.2, 22), (-1.3, 1.6, 8)]
        for r, (dy, ln, ang) in enumerate(rows):
            a = ang if side > 0 else 180 - ang
            ar = math.radians(a)
            for k in range(3):
                l2 = ln * (1 - 0.18 * k)
                cx = math.cos(ar) * l2 / 2
                cy = math.sin(ar) * l2 / 2 + dy + k * 0.05
                b.box(name, (cx, cy, -0.15 * k), (l2, 0.5, 0.3),
                      color if k < 2 else trim, "SmoothPlastic", rot=(0, 0, a))


def bolt(b, name, pos, scale, color, rot=None):
    """Zig-zag lightning bolt in the local XY plane."""
    pts = [(0.35, 1.0), (-0.25, 0.1), (0.25, 0.1), (-0.35, -1.0)]
    with b.at(pos, rot):
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            b.rod(name, (x0 * scale, y0 * scale, 0), (x1 * scale, y1 * scale, 0),
                  0.28 * scale, color, "Neon", shadow=False)


def x_panel(b, name, pos, w, h, frame, glow, rot=None):
    with b.at(pos, rot):
        b.box(name, (0, 0, 0), (w, h, 0.5), frame, "Slate")
        d = math.hypot(w, h) * 0.86
        ang = math.degrees(math.atan2(h, w))
        b.neon(name + "X", (0, 0, -0.28), (d, 0.22, 0.08), glow, rot=(0, 0, ang))
        b.neon(name + "X", (0, 0, -0.28), (d, 0.22, 0.08), glow, rot=(0, 0, -ang))
        for sx in (-1, 1):
            b.neon(name + "Edge", (sx * (w / 2 - 0.12), 0, -0.28), (0.12, h - 0.1, 0.08), glow)
        for sy in (-1, 1):
            b.neon(name + "Edge", (0, sy * (h / 2 - 0.12), -0.28), (w - 0.1, 0.12, 0.08), glow)


def skull(b, name, pos, bone, eye, horn, horn_tip, scale=1.0):
    """Horned voxel skull facing -Z."""
    s = scale
    with b.at(pos):
        b.box(name, (0, 0.2 * s, 0), (2.2 * s, 2.0 * s, 2.0 * s), bone, "SmoothPlastic")
        b.box(name, (0, -1.0 * s, -0.2 * s), (1.6 * s, 0.7 * s, 1.5 * s), bone, "SmoothPlastic")
        b.box(name, (0, 0.95 * s, 0.1 * s), (1.8 * s, 0.4 * s, 1.6 * s), bone, "SmoothPlastic")
        for sx in (-1, 1):
            b.box(name + "Socket", (sx * 0.5 * s, 0.15 * s, -1.0 * s), (0.62 * s, 0.5 * s, 0.1 * s),
                  "#101418", "SmoothPlastic")
            b.neon(name + "Eye", (sx * 0.5 * s, 0.15 * s, -1.06 * s), (0.34 * s, 0.26 * s, 0.06 * s),
                   eye)
        b.box(name + "Nose", (0, -0.35 * s, -1.02 * s), (0.26 * s, 0.3 * s, 0.08 * s), "#101418")
        for i in range(5):
            tx = (-0.6 + 0.3 * i) * s
            b.box(name + "Tooth", (tx, -0.72 * s, -0.98 * s), (0.18 * s, 0.22 * s, 0.1 * s),
                  "#f4f4ee")
        # horns: curl outwards then up
        for sx in (-1, 1):
            p = np.array([sx * 1.05 * s, 0.7 * s, 0.0])
            segs = [(sx * 0.55, 0.25), (sx * 0.5, 0.45), (sx * 0.3, 0.6), (sx * 0.1, 0.65),
                    (-sx * 0.05, 0.6)]
            w = 0.6 * s
            for i, (dx, dy) in enumerate(segs):
                q = p + np.array([dx * s, dy * s, 0])
                last = i == len(segs) - 1
                b.rod(name + "Horn", p, q, w, horn_tip if last else horn,
                      "Neon" if last else "SmoothPlastic", shadow=not last)
                p = q
                w *= 0.82


def crown(b, name, pos, color, gem_color, scale=1.0):
    s = scale
    with b.at(pos):
        b.box(name, (0, 0, 0), (1.6 * s, 0.45 * s, 1.6 * s), color, "Foil")
        for i, (x, z) in enumerate([(-0.6, -0.6), (0.6, -0.6), (-0.6, 0.6), (0.6, 0.6),
                                    (0, -0.6), (0, 0.6), (-0.6, 0), (0.6, 0)]):
            h = 0.7 if i < 4 else 0.45
            b.box(name, (x * s, (0.22 + h / 2) * s, z * s), (0.32 * s, h * s, 0.32 * s), color, "Foil")
        b.neon(name + "Gem", (0, 0.1 * s, -0.82 * s), (0.4 * s, 0.4 * s, 0.1 * s), gem_color,
               rot=(0, 0, 45))


def bone(b, name, pos, length, ry, color="#ece6d6"):
    with b.at(pos, (0, ry, 0)):
        b.box(name, (0, 0, 0), (length, 0.25, 0.25), color)
        for sx in (-1, 1):
            for sz in (-1, 1):
                b.ball(name, (sx * length / 2, 0, sz * 0.13), 0.32, color)


def mini_skull(b, name, pos, ry, color="#ece6d6"):
    with b.at(pos, (0, ry, 0)):
        b.box(name, (0, 0, 0), (0.7, 0.6, 0.7), color)
        b.box(name, (0, -0.35, -0.1), (0.5, 0.2, 0.5), color)
        for sx in (-1, 1):
            b.box(name + "Eye", (sx * 0.17, 0.02, -0.36), (0.18, 0.16, 0.04), "#1a0606")
