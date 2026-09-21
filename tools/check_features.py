#!/usr/bin/env python3
"""Checks features/*.lua with the Luau compiler / analyzer: syntax errors, the 200-locals limit and names that are
used but not defined (a missing dependency shows up as an unknown global).
    python tools/check_features.py <path to luau-compile> <path to luau-analyze>
"""
import glob, os, re, subprocess, sys

compiler, analyzer = sys.argv[1], sys.argv[2]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Roblox and executor globals that are legitimately not defined in a file
KNOWN = set("""Enum Vector3 Color3 UDim2 Instance CFrame game task Vector2 workspace UDim isfile sethiddenproperty getgenv
writefile readfile isnetworkowner getcustomasset gethiddenproperty Ray setclipboard newcclosure mouse1click makefolder
isfolder hookmetamethod checkcaller TERKANUI RaycastParams warn setfpscap request mousemoverel getnamecallmethod gethui
Random OverlapParams NumberSequence Font settings ColorSequence NumberRange TweenInfo Rect Region3 BrickColor Axes Faces
listfiles delfile queue_on_teleport keypress keyrelease mouse1press mouse1release identifyexecutor http_request""".split())

bad = 0
for path in sorted(glob.glob(os.path.join(root, "features", "*.lua"))):
    name = os.path.basename(path)
    p = subprocess.run([compiler, "--binary", path], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        print("%-28s COMPILE ERROR: %s" % (name, p.stderr.strip().splitlines()[0] if p.stderr.strip() else "?"))
        bad += 1
        continue
    a = subprocess.run([analyzer, path], capture_output=True, text=True, encoding="utf-8", errors="replace")
    unknown = sorted({m for m in re.findall(r"Unknown global '(\w+)'", a.stdout + a.stderr) if m not in KNOWN})
    if unknown:
        print("%-28s missing: %s" % (name, ", ".join(unknown)))
        bad += 1
    else:
        print("%-28s ok" % name)
print("\n%d file(s) with problems" % bad)
