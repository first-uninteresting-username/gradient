#!/usr/bin/env python3
"""Writes track/chunks/*.tscn from the table below.

The .tscn files are the source of truth and can be edited in Godot; this script is
just a convenient way to author the starter catalogue consistently.
Run: nix shell nixpkgs#python3 -c python3 tools/make_chunks.py
"""
import json
import os

FW, FN, HP, TU = "flat_wide", "flat_narrow", "halfpipe", "tube"


def S(length, **kw):
    d = {"len": float(length)}
    for k, v in kw.items():
        d[k] = float(v) if isinstance(v, int) and not isinstance(v, bool) else v
    return d


CHUNKS = [
    # id, name, tags, difficulty, weight, min, max, entry, exit, adapter, sections, slots, gate_spacing
    ("straight_wide", "Wide straight", ["straight", "flat", "breather", "scenic"], 1, 1.0, 0, 1000, FW, FW, False,
     [S(50)], [], 25),
    ("straight_narrow", "Narrow straight", ["straight", "flat", "breather", "scenic"], 2, 0.8, 0, 1000, FN, FN, False,
     [S(50)], [], 25),
    ("s_bend", "Gentle S-bend", ["turn", "scenic"], 2, 1.0, 0, 80, FW, FW, False,
     [S(10), S(30, yaw=18), S(30, yaw=-18), S(10)], [], 25),
    ("turn_left", "Left 30°", ["turn", "scenic"], 2, 1.0, 0, 80, FW, FW, False,
     [S(10), S(50, yaw=-30), S(10)], [], 25),
    ("turn_right", "Right 30°", ["turn", "scenic"], 2, 1.0, 0, 80, FW, FW, False,
     [S(10), S(50, yaw=30), S(10)], [], 25),
    ("banked_sweeper", "Banked sweeper", ["turn", "scenic"], 4, 0.9, 0, 80, FW, FW, False,
     [S(10), S(20, bank=12), S(80, yaw=-60), S(20, bank=0), S(10)], [], 25),
    ("step_down", "Step-down drop", ["height", "scenic"], 3, 0.9, 0, 1000, FW, FW, False,
     [S(16), S(4, floor=False, drop=3), S(30)], [], 25),
    ("ramp_gap", "Launch ramp + gap", ["height", "scenic"], 5, 0.8, 0, 1000, FW, FW, False,
     [S(14), S(12, pitch=26, launch=True), S(8, pitch=0, floor=False, drop=3), S(36)], [], 25),
    ("double_hump", "Double hump", ["height", "scenic"], 3, 0.9, 0, 1000, FW, FW, False,
     [S(10), S(10, pitch=10), S(14, pitch=-10), S(10, pitch=0), S(6),
      S(10, pitch=10), S(14, pitch=-10), S(10, pitch=0), S(10)], [], 25),
    ("halfpipe_run", "Halfpipe run", ["walls", "breather", "scenic"], 3, 1.0, 0, 1000, HP, HP, False,
     [S(60)], [], 25),
    ("tube", "Enclosed tube", ["walls", "breather", "scenic"], 4, 1.0, 0, 1000, TU, TU, False,
     [S(60)], [], 25),
    ("tube_hole", "Tube with a hole", ["walls", "hazard"], 4, 0.9, 0, 1000, TU, TU, False,
     [S(16), S(8, hole=[-1.6, 1.6]), S(12), S(8, hole=[-1.6, 1.6]), S(16)], [], 25),
    ("scatter_blocks", "Scattered blocks", ["hazard"], 1, 1.4, 0, 1000, FW, FW, False,
     [S(80)], [{"type": "scatter", "from": 12.0, "to": 72.0}], 0),
    ("slalom", "Slalom walls", ["hazard"], 2, 1.1, 0, 1000, FW, FW, False,
     [S(90)], [{"type": "slalom", "from": 14.0, "to": 84.0}], 0),
    ("picket", "Picket line", ["hazard"], 2, 1.1, 0, 1000, FW, FW, False,
     [S(70)], [{"type": "picket", "at": [20.0, 46.0]}], 0),
    ("narrow_blocks", "Narrow blocks", ["hazard"], 3, 0.9, 0, 1000, FN, FN, False,
     [S(70)], [{"type": "slalom", "from": 14.0, "to": 64.0}], 0),
    ("sliding_block", "Sliding blocks", ["hazard", "moving"], 3, 1.0, 0, 1000, FW, FW, False,
     [S(80)], [{"type": "slider", "at": [20.0, 42.0, 64.0]}], 0),
    ("blocks_turn", "Blocks in a turn", ["hazard", "turn"], 4, 0.9, 0, 80, FW, FW, False,
     [S(10), S(60, yaw=30), S(10)], [{"type": "scatter", "from": 14.0, "to": 66.0}], 0),
    ("rising_block", "Rising blocks", ["hazard", "moving"], 4, 0.9, 0, 1000, FW, FW, False,
     [S(80)], [{"type": "riser", "at": [24.0, 56.0]}], 0),
    ("halfpipe_blocks", "Halfpipe blocks", ["hazard", "walls"], 4, 0.8, 0, 1000, HP, HP, False,
     [S(70)], [{"type": "scatter", "from": 12.0, "to": 62.0}], 0),
    ("gauntlet", "Gauntlet", ["hazard", "moving"], 6, 0.9, 0, 1000, FW, FW, False,
     [S(110)], [{"type": "picket", "at": [18.0]}, {"type": "slider", "at": [40.0]},
                {"type": "scatter", "from": 58.0, "to": 76.0}, {"type": "riser", "at": [94.0]}], 0),
    # Profile adapters.
    ("adapter_wide_narrow", "Adapter wide → narrow", ["adapter", "flat"], 2, 0.6, 0, 1000, FW, FN, True,
     [S(6), S(12, profile=FN), S(6)], [], 25),
    ("adapter_narrow_wide", "Adapter narrow → wide", ["adapter", "flat"], 1, 0.6, 0, 1000, FN, FW, True,
     [S(6), S(12, profile=FW), S(6)], [], 25),
    ("adapter_wide_halfpipe", "Adapter wide → halfpipe", ["adapter"], 2, 0.6, 0, 1000, FW, HP, True,
     [S(6), S(14, profile=HP), S(6)], [], 25),
    ("adapter_halfpipe_wide", "Adapter halfpipe → wide", ["adapter"], 1, 0.6, 0, 1000, HP, FW, True,
     [S(6), S(14, profile=FW), S(6)], [], 25),
    ("adapter_wide_tube", "Adapter wide → tube", ["adapter"], 3, 0.6, 0, 1000, FW, TU, True,
     [S(6), S(16, profile=TU), S(6)], [], 25),
    ("adapter_tube_wide", "Adapter tube → wide", ["adapter"], 1, 0.6, 0, 1000, TU, FW, True,
     [S(6), S(16, profile=FW), S(6)], [], 25),
]


def gd(v):
    """Godot text-resource literal."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "[" + ", ".join(gd(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{\n" + ",\n".join(f"{gd(k)}: {gd(x)}" for k, x in v.items()) + "\n}"
    raise TypeError(v)


def main():
    root = os.path.join(os.path.dirname(__file__), "..", "track", "chunks")
    os.makedirs(root, exist_ok=True)
    for (cid, name, tags, diff, weight, vmin, vmax, entry, exit_, adapter, sections, slots, gates) in CHUNKS:
        length = sum(s["len"] for s in sections)
        tags_lit = "PackedStringArray(" + ", ".join(json.dumps(t) for t in tags) + ")"
        text = f"""[gd_scene format=3]

[ext_resource type="Script" path="res://track/chunk.gd" id="1_chunk"]
[ext_resource type="Script" path="res://track/chunk_info.gd" id="2_info"]

[sub_resource type="Resource" id="Resource_info"]
script = ExtResource("2_info")
id = &"{cid}"
display_name = {json.dumps(name, ensure_ascii=False)}
tags = {tags_lit}
difficulty = {diff}
weight = {float(weight)!r}
min_speed = {float(vmin)!r}
max_speed = {float(vmax)!r}
length = {float(length)!r}
entry_profile = &"{entry}"
exit_profile = &"{exit_}"
adapter = {gd(adapter)}
sections = {gd(sections)}
hazard_slots = {gd(slots)}
gate_spacing = {float(gates)!r}

[node name="{cid}" type="Node3D"]
script = ExtResource("1_chunk")
info = SubResource("Resource_info")
"""
        with open(os.path.join(root, cid + ".tscn"), "w", encoding="utf-8") as f:
            f.write(text)
    print(f"wrote {len(CHUNKS)} chunks")


if __name__ == "__main__":
    main()
