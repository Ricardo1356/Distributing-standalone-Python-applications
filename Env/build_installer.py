#!/usr/bin/env python3
"""
build_installer.py  –  one‑shot builder, no code‑signing
---------------------------------------------------------
layout expected:

project_root/
│
├─ src/                        ← your real app (has requirements.txt)
├─ tools/
│    └─ package_app.py
├─ installer/
│    └─ MinimalInstallerVisiblePS.iss
└─ build_installer.py          ← this file
"""

import os, shutil, subprocess, sys, zipfile
from pathlib import Path

# ─────────── configurable knobs ────────────
APP_NAME     = "MyPythonApp"
APP_VERSION  = "1.0.0"
ENTRY_FILE   = "core.py"

SOURCE_APP_DIR  = Path("src")
PY_PACKAGER     = Path("tools", "package_app.py")
ISS_TEMPLATE    = Path("installer", "MinimalInstallerVisiblePS.iss")

BUILD_DIR = Path("build")
DIST_DIR  = Path("dist")
OUTPUT_NAME = f"{APP_NAME}_{APP_VERSION}"
# ───────────────────────────────────────────

def run(cmd, **kw):
    print(">", " ".join(map(str, cmd)))
    subprocess.check_call(cmd, **kw)

def clean(p: Path):
    if p.exists():
        shutil.rmtree(p)
    p.mkdir(parents=True, exist_ok=True)

def main() -> None:
    clean(BUILD_DIR)
    clean(DIST_DIR)

    # ----- step 1  run packager ------------------------------------------------
    pkg_zip = Path.cwd() / f"{APP_NAME}_pkg.zip"
    run([sys.executable, PY_PACKAGER,
         SOURCE_APP_DIR,
         "--app-name", APP_NAME,
         "--entry-file", ENTRY_FILE,
         "--version", APP_VERSION,
         "-n", pkg_zip.name])

    with zipfile.ZipFile(pkg_zip) as zf:
        zf.extractall(BUILD_DIR)
    pkg_zip.unlink()

    build_subdir = next(BUILD_DIR.iterdir())   # first folder inside build/
    print("Build folder:", build_subdir)

    # ----- step 2  compile Inno Setup -----------------------------------------
    iscc = shutil.which("ISCC.exe")
    if not iscc:
        sys.exit("ERROR: ISCC.exe not found (install Inno Setup 6 and add to PATH)")

    run([iscc,
         f"/O{DIST_DIR}",
         f"/DAppVer={APP_VERSION}",
         f"/DOutputName={OUTPUT_NAME}",
         f"/DBuildDir={build_subdir}",
         ISS_TEMPLATE])

    exe_path = DIST_DIR / f"{OUTPUT_NAME}.exe"
    print("\n✓ Installer built →", exe_path)

if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"\n✖ Build failed (exit {e.returncode})")
