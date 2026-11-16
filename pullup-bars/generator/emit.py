"""Writers: Roblox .rbxmx model files, standalone Luau build scripts, and the
compact JSON the web preview reads."""
from __future__ import annotations

import base64
import struct
from xml.sax.saxutils import escape

from core import hex_rgb

MATERIAL = {
    "Plastic": 256, "SmoothPlastic": 272, "Neon": 288, "Marble": 784, "Slate": 800,
    "Granite": 832, "Foil": 1072, "Metal": 1088, "Fabric": 1312, "Ice": 1536,
    "Glass": 1568, "DiamondPlate": 1056,
}
SHAPE = {"Ball": 0, "Block": 1, "Cylinder": 2}
TEXTURE = {
    "sparkles": "rbxasset://textures/particles/sparkles_main.dds",
    "fire": "rbxasset://textures/particles/fire_main.dds",
    "smoke": "rbxasset://textures/particles/smoke_main.dds",
}
GROUPS = ["Frame", "Decor", "FX"]


def f(v):
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# --------------------------------------------------------------------------
# rbxmx
# --------------------------------------------------------------------------

class Ref:
    def __init__(self):
        self.n = 0

    def __call__(self):
        self.n += 1
        return "RBX%08X" % self.n


def _cf(name, pos, rot):
    r = rot
    return ("<CoordinateFrame name=\"%s\"><X>%s</X><Y>%s</Y><Z>%s</Z>"
            "<R00>%s</R00><R01>%s</R01><R02>%s</R02>"
            "<R10>%s</R10><R11>%s</R11><R12>%s</R12>"
            "<R20>%s</R20><R21>%s</R21><R22>%s</R22></CoordinateFrame>"
            % (name, f(pos[0]), f(pos[1]), f(pos[2]),
               f(r[0][0]), f(r[0][1]), f(r[0][2]),
               f(r[1][0]), f(r[1][1]), f(r[1][2]),
               f(r[2][0]), f(r[2][1]), f(r[2][2])))


def _color3(name, hexc):
    r, g, b = hex_rgb(hexc)
    return "<Color3 name=\"%s\"><R>%s</R><G>%s</G><B>%s</B></Color3>" % (
        name, f(r / 255), f(g / 255), f(b / 255))


def _color3u8(hexc):
    r, g, b = hex_rgb(hexc)
    return "<Color3uint8 name=\"Color3uint8\">%d</Color3uint8>" % (0xFF000000 | r << 16 | g << 8 | b)


def _numseq(name, keys):
    return "<NumberSequence name=\"%s\">%s </NumberSequence>" % (
        name, " ".join("%s %s 0" % (f(t), f(v)) for t, v in keys))


def _colseq(name, colors):
    c0 = [c / 255 for c in hex_rgb(colors[0])]
    c1 = [c / 255 for c in hex_rgb(colors[-1])]
    return "<ColorSequence name=\"%s\">0 %s %s %s 0 1 %s %s %s 0 </ColorSequence>" % (
        name, f(c0[0]), f(c0[1]), f(c0[2]), f(c1[0]), f(c1[1]), f(c1[2]))


def _range(name, r):
    return "<NumberRange name=\"%s\">%s %s </NumberRange>" % (name, f(r[0]), f(r[1]))


def attributes_blob(attrs):
    """Encode Instance attributes the way Roblox stores them in files."""
    out = struct.pack("<I", len(attrs))
    for k, v in attrs.items():
        kb = k.encode()
        out += struct.pack("<I", len(kb)) + kb
        if isinstance(v, bool):
            out += b"\x03" + (b"\x01" if v else b"\x00")
        elif isinstance(v, (int, float)):
            out += b"\x06" + struct.pack("<d", float(v))
        else:
            vb = str(v).encode()
            out += b"\x02" + struct.pack("<I", len(vb)) + vb
    return base64.b64encode(out).decode()


def _part_xml(p, pref, ref):
    cls = "Part"
    props = [
        "<string name=\"Name\">%s</string>" % escape(p["name"]),
        "<bool name=\"Anchored\">true</bool>",
        "<bool name=\"CanCollide\">%s</bool>" % ("true" if p["collide"] else "false"),
        "<bool name=\"CanTouch\">%s</bool>" % ("true" if p["collide"] else "false"),
        "<bool name=\"CanQuery\">%s</bool>" % ("true" if p["collide"] else "false"),
        "<bool name=\"CastShadow\">%s</bool>" % ("true" if p["shadow"] else "false"),
        "<bool name=\"Locked\">false</bool>",
        _cf("CFrame", p["pos"], p["rot"]),
        _color3u8(p["color"]),
        "<token name=\"Material\">%d</token>" % MATERIAL[p["mat"]],
        "<float name=\"Transparency\">%s</float>" % f(p["transparency"]),
        "<float name=\"Reflectance\">%s</float>" % f(p["reflectance"]),
        "<token name=\"shape\">%d</token>" % SHAPE[p["shape"]],
        "<Vector3 name=\"size\"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>" % tuple(f(v) for v in p["size"]),
        "<token name=\"TopSurface\">0</token>",
        "<token name=\"BottomSurface\">0</token>",
    ]
    kids = []
    for a in p.get("attachments", []):
        kids.append("<Item class=\"Attachment\" referent=\"%s\"><Properties>"
                    "<string name=\"Name\">%s</string>%s</Properties></Item>"
                    % (ref(), a["name"], _cf("CFrame", a["pos"], [[1, 0, 0], [0, 1, 0], [0, 0, 1]])))
    lt = p.get("light")
    if lt:
        kids.append("<Item class=\"PointLight\" referent=\"%s\"><Properties>"
                    "<string name=\"Name\">Glow</string>%s"
                    "<float name=\"Brightness\">%s</float><float name=\"Range\">%s</float>"
                    "<bool name=\"Shadows\">false</bool><bool name=\"Enabled\">true</bool>"
                    "</Properties></Item>"
                    % (ref(), _color3("Color", lt["color"]), f(lt["brightness"]), f(lt["range"])))
    e = p.get("emitter")
    if e:
        kids.append(
            "<Item class=\"ParticleEmitter\" referent=\"%s\"><Properties>"
            "<string name=\"Name\">Particles</string>"
            "%s%s%s%s%s%s%s%s"
            "<float name=\"Rate\">%s</float>"
            "<float name=\"LightEmission\">%s</float>"
            "<Vector2 name=\"SpreadAngle\"><X>%s</X><Y>%s</Y></Vector2>"
            "<Vector3 name=\"Acceleration\"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>"
            "<Content name=\"Texture\"><url>%s</url></Content>"
            "<token name=\"EmissionDirection\">1</token>"
            "<bool name=\"Enabled\">true</bool>"
            "</Properties></Item>"
            % (ref(), _colseq("Color", e["colors"]), _numseq("Size", e["size"]),
               _numseq("Transparency", e["transparency"]), _range("Lifetime", e["lifetime"]),
               _range("Speed", e["speed"]), _range("RotSpeed", e["rotspeed"]),
               _range("Rotation", (0, 360)), "",
               f(e["rate"]), f(e["light_emission"]), f(e["spread"][0]), f(e["spread"][1]),
               f(e["accel"][0]), f(e["accel"][1]), f(e["accel"][2]), TEXTURE[e["texture"]]))
    return "<Item class=\"%s\" referent=\"%s\"><Properties>%s</Properties>%s</Item>" % (
        cls, pref, "".join(props), "".join(kids))


def model_xml(tier, name, parts, ref):
    mref = ref()
    part_refs = [ref() for _ in parts]
    primary = next(r for r, p in zip(part_refs, parts) if p.get("primary"))
    groups = []
    for g in GROUPS:
        items = "".join(_part_xml(p, r, ref) for p, r in zip(parts, part_refs) if p["group"] == g)
        if items:
            groups.append("<Item class=\"Model\" referent=\"%s\"><Properties>"
                          "<string name=\"Name\">%s</string></Properties>%s</Item>"
                          % (ref(), g, items))
    attrs = attributes_blob({"Equipment": "PullUpBar", "Tier": tier, "TierName": name})
    tags = base64.b64encode(b"PullUpBar").decode()
    return ("<Item class=\"Model\" referent=\"%s\"><Properties>"
            "<string name=\"Name\">%s</string>"
            "<Ref name=\"PrimaryPart\">%s</Ref>"
            "<OptionalCoordinateFrame name=\"WorldPivotData\">%s</OptionalCoordinateFrame>"
            "<BinaryString name=\"AttributesSerialize\">%s</BinaryString>"
            "<BinaryString name=\"Tags\">%s</BinaryString>"
            "</Properties>%s</Item>"
            % (mref, escape(model_name(tier, name)), primary,
               _cf("CFrame", (0, 0, 0), [[1, 0, 0], [0, 1, 0], [0, 0, 1]]).replace(
                   "<CoordinateFrame name=\"CFrame\">", "<CFrame>").replace(
                   "</CoordinateFrame>", "</CFrame>"),
               attrs, tags, "".join(groups)))


def model_name(tier, name):
    return "PullUpBar_T%d_%s" % (tier, name.replace(" ", ""))


HEADER = ("<roblox xmlns:xmime=\"http://www.w3.org/2005/05/xmlmime\" "
          "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
          "xsi:noNamespaceSchemaLocation=\"http://www.roblox.com/roblox.xsd\" version=\"4\">")


def write_rbxmx(path, models, folder=None):
    ref = Ref()
    body = "".join(model_xml(t, n, parts, ref) for t, n, parts in models)
    if folder:
        body = ("<Item class=\"Folder\" referent=\"%s\"><Properties><string name=\"Name\">%s"
                "</string></Properties>%s</Item>" % (ref(), folder, body))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(HEADER + body + "</roblox>\n")


# --------------------------------------------------------------------------
# Luau build script
# --------------------------------------------------------------------------

LUAU_BUILDER = r'''
local function seq(keys)
	local kps = {}
	for _, k in ipairs(keys) do
		table.insert(kps, NumberSequenceKeypoint.new(k[1], k[2]))
	end
	return NumberSequence.new(kps)
end

local function build(spec)
	local model = Instance.new("Model")
	model.Name = spec.name
	local groups = {}
	for _, g in ipairs({ "Frame", "Decor", "FX" }) do
		local m = Instance.new("Model")
		m.Name = g
		m.Parent = model
		groups[g] = m
	end
	for _, p in ipairs(spec.parts) do
		local part = Instance.new("Part")
		part.Name = p.n
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Shape = Enum.PartType[p.sh]
		part.Size = Vector3.new(p.s[1], p.s[2], p.s[3])
		part.CFrame = CFrame.new(table.unpack(p.cf))
		part.Color = Color3.fromRGB(p.c[1], p.c[2], p.c[3])
		part.Material = Enum.Material[p.m]
		part.Transparency = p.t or 0
		part.CanCollide = p.cc == true
		part.CanTouch = p.cc == true
		part.CanQuery = p.cc == true
		part.CastShadow = p.cs == true
		if p.a then
			for _, a in ipairs(p.a) do
				local att = Instance.new("Attachment")
				att.Name = a[1]
				att.CFrame = CFrame.new(a[2], a[3], a[4])
				att.Parent = part
			end
		end
		if p.l then
			local light = Instance.new("PointLight")
			light.Name = "Glow"
			light.Color = Color3.fromRGB(p.l.c[1], p.l.c[2], p.l.c[3])
			light.Brightness = p.l.b
			light.Range = p.l.r
			light.Parent = part
		end
		if p.e then
			local e = p.e
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "Particles"
			pe.Texture = e.tex
			pe.Color = ColorSequence.new(
				Color3.fromRGB(e.c0[1], e.c0[2], e.c0[3]),
				Color3.fromRGB(e.c1[1], e.c1[2], e.c1[3])
			)
			pe.Size = seq(e.size)
			pe.Transparency = seq(e.tr)
			pe.Lifetime = NumberRange.new(e.life[1], e.life[2])
			pe.Speed = NumberRange.new(e.speed[1], e.speed[2])
			pe.RotSpeed = NumberRange.new(e.rot[1], e.rot[2])
			pe.Rotation = NumberRange.new(0, 360)
			pe.Rate = e.rate
			pe.LightEmission = e.le
			pe.SpreadAngle = Vector2.new(e.spread[1], e.spread[2])
			pe.Acceleration = Vector3.new(e.acc[1], e.acc[2], e.acc[3])
			pe.Parent = part
		end
		part.Parent = groups[p.g]
		if p.pp then
			model.PrimaryPart = part
		end
	end
	for _, g in pairs(groups) do
		if #g:GetChildren() == 0 then
			g:Destroy()
		end
	end
	model.WorldPivot = CFrame.new()
	model:SetAttribute("Equipment", "PullUpBar")
	model:SetAttribute("Tier", spec.tier)
	model:SetAttribute("TierName", spec.tierName)
	model:AddTag("PullUpBar")
	return model
end
'''


def _lt(v):
    return "{" + ",".join(v) + "}"


def _rgb(h):
    return "{%d,%d,%d}" % hex_rgb(h)


def luau_part(p):
    r = p["rot"]
    cf = [p["pos"][0], p["pos"][1], p["pos"][2], r[0][0], r[0][1], r[0][2], r[1][0], r[1][1],
          r[1][2], r[2][0], r[2][1], r[2][2]]
    fields = [
        "n=%r" % p["name"], "g=%r" % p["group"], "sh=%r" % p["shape"],
        "cf=" + _lt(f(v) for v in cf), "s=" + _lt(f(v) for v in p["size"]),
        "c=" + _rgb(p["color"]), "m=%r" % p["mat"],
    ]
    if p["transparency"]:
        fields.append("t=" + f(p["transparency"]))
    if p["collide"]:
        fields.append("cc=true")
    if p["shadow"]:
        fields.append("cs=true")
    if p.get("primary"):
        fields.append("pp=true")
    if p.get("attachments"):
        fields.append("a={" + ",".join("{%r,%s,%s,%s}" % (a["name"], *(f(v) for v in a["pos"]))
                                       for a in p["attachments"]) + "}")
    if p.get("light"):
        lt = p["light"]
        fields.append("l={c=%s,b=%s,r=%s}" % (_rgb(lt["color"]), f(lt["brightness"]), f(lt["range"])))
    if p.get("emitter"):
        e = p["emitter"]
        fields.append(
            "e={tex=%r,c0=%s,c1=%s,size={%s},tr={%s},life={%s,%s},speed={%s,%s},rot={%s,%s},"
            "rate=%s,le=%s,spread={%s,%s},acc={%s,%s,%s}}" % (
                TEXTURE[e["texture"]], _rgb(e["colors"][0]), _rgb(e["colors"][-1]),
                ",".join("{%s,%s}" % (f(t), f(v)) for t, v in e["size"]),
                ",".join("{%s,%s}" % (f(t), f(v)) for t, v in e["transparency"]),
                f(e["lifetime"][0]), f(e["lifetime"][1]), f(e["speed"][0]), f(e["speed"][1]),
                f(e["rotspeed"][0]), f(e["rotspeed"][1]), f(e["rate"]), f(e["light_emission"]),
                f(e["spread"][0]), f(e["spread"][1]), *(f(v) for v in e["accel"])))
    return "\t{" + ",".join(fields).replace("'", '"') + "},"


def write_luau(path, tier, name, parts, offset_x=0):
    lines = [
        "--!nocheck",
        "-- Builds %s (tier %d pull-up bar) in Workspace." % (model_name(tier, name), tier),
        "-- Paste into the Studio command bar, or run it once as a Script.",
        "-- Generated by pullup-bars/generator/build.py - edit the generator, not this file.",
        LUAU_BUILDER,
        "local spec = { name = %r, tier = %d, tierName = %r, parts = {" % (
            model_name(tier, name), tier, name),
    ]
    lines[-1] = lines[-1].replace("'", '"')
    lines += [luau_part(p) for p in parts]
    lines += [
        "} }",
        "",
        "local model = build(spec)",
        "model:PivotTo(CFrame.new(%s, 0, 0))" % f(offset_x),
        "model.Parent = workspace",
        "pcall(function()",
        "\tgame:GetService(\"Selection\"):Set({ model })",
        "end)",
        "return model",
        "",
    ]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


# --------------------------------------------------------------------------
# Preview JSON
# --------------------------------------------------------------------------

def preview_model(tier, name, sky, parts):
    out = []
    for p in parts:
        r = p["rot"]
        rec = [
            {"Block": 0, "Ball": 1, "Cylinder": 2}[p["shape"]],
            [round(v, 3) for v in p["pos"]],
            [round(v, 4) for row in r for v in row],
            [round(v, 3) for v in p["size"]],
            p["color"],
            p["mat"],
            round(p["transparency"], 2),
        ]
        out.append(rec)
    emitters = [{"pos": [round(v, 2) for v in p["pos"]], "size": p["size"],
                 "colors": p["emitter"]["colors"], "accel": p["emitter"]["accel"],
                 "speed": p["emitter"]["speed"], "rate": p["emitter"]["rate"],
                 "life": p["emitter"]["lifetime"], "kind": p["emitter"]["texture"]}
                for p in parts if p.get("emitter")]
    return {"tier": tier, "name": name, "sky": sky, "parts": out, "emitters": emitters}
