#!/usr/bin/env python3
"""
Checks the hub and every feature file with the real Luau compiler / analyzer.

  * syntax errors and the 200-locals limit   -> luau-compile fails
  * names that are used but not defined      -> luau-analyze reports an "Unknown global"
    (Roblox and executor globals are listed in KNOWN; anything else is a typo or a missing dependency)

    python tools/check.py                 # hub + features/
    python tools/check.py --wrapper OUT   # also write a wrapper file for the executor (see below)

The luau tools are looked for in tools/bin/ (download luau-windows.zip from https://github.com/luau-lang/luau/releases
and unzip it there) and on the PATH. tools/bin/ is not committed.

Executor check (what the compiler cannot know: Solara's own quirks): --wrapper writes a file that embeds the hub in a
long string, loadstrings it and stores the result in getgenv().__TU_ERR. Run it in the executor, then read
getgenv().__TU_ERR: "OK" or the compile error. (A plain execute of a script with a compile error looks like success
because the OLD version keeps running.)
"""
import glob
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# Roblox and executor globals that are legitimately not defined in a file
KNOWN = set("""Enum Vector3 Color3 UDim2 Instance CFrame game task Vector2 workspace UDim isfile sethiddenproperty getgenv
writefile readfile isnetworkowner getcustomasset gethiddenproperty Ray setclipboard newcclosure mouse1click makefolder
isfolder hookmetamethod checkcaller TERKANUI RaycastParams warn setfpscap request mousemoverel getnamecallmethod gethui
Random OverlapParams NumberSequence Font settings ColorSequence NumberRange TweenInfo Rect Region3 BrickColor Axes Faces
listfiles delfile queue_on_teleport keypress keyrelease mouse1press mouse1release identifyexecutor http_request
getrawmetatable setreadonly isreadonly hookfunction getgc getconnections getsenv cloneref clonefunction
fireproximityprompt firetouchinterest fireclickdetector sethiddenproperty setsimulationradius getrenv getfenv
syn fluxus PhysicalProperties Vector3int16 Vector2int16 CatalogSearchParams DockWidgetPluginGuiInfo DateTime
UserSettings Stats stats version elapsedTime tick time utf8 typeof ColorSequenceKeypoint NumberSequenceKeypoint
CFrame Vector3int16 PathWaypoint Ray""".split())


def tool(name):
    exe = name + (".exe" if os.name == "nt" else "")
    local = os.path.join(HERE, "bin", exe)
    if os.path.isfile(local):
        return local
    found = shutil.which(name)
    if found:
        return found
    sys.exit("%s not found: unzip the Luau release into tools/bin/ (see the top of tools/check.py)" % name)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")


# Lints that point at dead or half-finished code. Only checked in the hand-written files: the feature files are cut
# out of the hub by build_features.py and carry shared locals (playerDD, aimTarget ...) that not every feature uses.
LINTS = ("LocalUnused", "FunctionUnused", "ImplicitReturn")
LINTED = {"TerkanUniversal.lua", "TerkanUI.lua", "Terkan.lua"}


def check_file(compiler, analyzer, path):
    """returns a list of problems (empty = fine)"""
    p = run([compiler, "--binary", path])
    if p.returncode != 0:
        first = (p.stderr or p.stdout).strip().splitlines()
        return ["COMPILE ERROR: " + (first[0] if first else "?")]
    a = run([analyzer, path])
    out = a.stdout + a.stderr
    problems = []
    unknown = sorted({m for m in re.findall(r"Unknown global '(\w+)'", out) if m not in KNOWN})
    if unknown:
        problems.append("unknown global: " + ", ".join(unknown))
    if os.path.basename(path) in LINTED:
        for line, kind, msg in re.findall(r"\((\d+),\d+\): (%s): ([^;\n]+)" % "|".join(LINTS), out):
            problems.append("line %s %s: %s" % (line, kind, msg))
    return problems


def write_wrapper(out):
    hub = os.path.join(ROOT, "TerkanUniversal.lua")
    with open(hub, encoding="utf-8", newline="") as f:
        text = f.read().replace("\r\n", "\n")
    assert "]==]" not in text, "the hub contains ]==], pick another long-string level"
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("local src = [==[\n" + text + "]==]\n")
        f.write('local fn, err = loadstring(src, "=TerkanUniversal")\n')
        f.write('getgenv().__TU_ERR = fn and "OK" or tostring(err)\n')
    print("wrapper written:", out)


def main():
    if "--wrapper" in sys.argv:
        write_wrapper(sys.argv[sys.argv.index("--wrapper") + 1])
    compiler, analyzer = tool("luau-compile"), tool("luau-analyze")
    targets = [os.path.join(ROOT, "TerkanUniversal.lua"), os.path.join(ROOT, "TerkanUI.lua"),
               os.path.join(ROOT, "Terkan.lua")]
    targets += sorted(glob.glob(os.path.join(ROOT, "features", "*.lua")))
    targets += sorted(glob.glob(os.path.join(ROOT, "examples", "*.lua")))
    bad = 0
    for path in targets:
        problems = check_file(compiler, analyzer, path)
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        print("%-34s %s" % (rel, "ok" if not problems else "; ".join(problems)))
        bad += bool(problems)
    print("\n%d of %d file(s) with problems" % (bad, len(targets)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
