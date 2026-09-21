#!/usr/bin/env python3
"""
One command builds everything.

    src/NN_name.lua   the source of the hub, one file per tab (00_core = helpers and shared state)
        |  bundle (plain concatenation, in file name order)
        v
    TerkanUniversal.lua      the hub that people load
        |  tools/build_features.py
        v
    features/*.lua           every feature as a file of its own, features/_core.lua, features/README.md
    features/manifest.json   machine readable index of all features (used by Terkan.lua)
        |  tools/check.py
        v
    compile + analyze of everything

Edit the files in src/, never TerkanUniversal.lua or features/ (they are overwritten).

    python tools/build.py              # bundle, build features, manifest, check
    python tools/build.py --no-check   # skip the compiler check
    python tools/build.py --bump 2.3.0 # also set the version (version.txt and U.Version in the hub)
"""
import glob
import io
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import build_features as bf  # noqa: E402


def bundle():
    parts = sorted(glob.glob(os.path.join(ROOT, "src", "[0-9][0-9]_*.lua")))
    if not parts:
        sys.exit("no files in src/")
    text = ""
    for p in parts:
        with io.open(p, encoding="utf-8", newline="") as f:
            text += f.read().replace("\r\n", "\n")
    return text, parts


def bump(text, version):
    text, n = re.subn(r'(U\.Version = )"[^"]*"', r'\g<1>"%s"' % version, text, count=1)
    if n != 1:
        sys.exit('U.Version = "..." not found in src/')
    return text


def main():
    args = sys.argv[1:]
    text, parts = bundle()
    if "--bump" in args:
        version = args[args.index("--bump") + 1]
        # the version lives in the core chunk of src/
        core = parts[0]
        with io.open(core, encoding="utf-8", newline="") as f:
            body = f.read()
        with io.open(core, "w", encoding="utf-8", newline="\n") as f:
            f.write(bump(body, version))
        with io.open(os.path.join(ROOT, "version.txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write(version + "\n")
        text, parts = bundle()

    hub = os.path.join(ROOT, "TerkanUniversal.lua")
    with io.open(hub, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("bundled %d files -> TerkanUniversal.lua (%d lines)" % (len(parts), text.count("\n")))

    subprocess.run([sys.executable, os.path.join(HERE, "build_features.py")], check=True, cwd=ROOT)

    version = re.search(r'U\.Version = "([^"]*)"', text).group(1)
    manifest = {
        "version": version,
        "base": bf.BASE_URL,
        "features": [dict(name=f["name"], title=f["title"], about=f["about"], file="features/%s.lua" % f["name"])
                     for f in bf.FEATURES],
        "aliases": [dict(name=n, target=t, about=a) for n, t, a in bf.ALIASES],
    }
    with io.open(os.path.join(ROOT, "features", "manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("manifest: %d features, %d pointers" % (len(manifest["features"]), len(manifest["aliases"])))

    if "--no-check" not in args:
        sys.exit(subprocess.run([sys.executable, os.path.join(HERE, "check.py")], cwd=ROOT).returncode)


if __name__ == "__main__":
    main()
