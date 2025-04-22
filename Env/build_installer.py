#!/usr/bin/env python3
"""
build_installer.py  –  one‑shot builder that produces a single .exe

Usage:
  python build_installer.py \
    --app-folder   /path/to/your/project \
    --iss          /path/to/installer.iss \
    --output-exe   /where/to/FinalSetup.exe \
    [--entry-file  core.py] \
    [--app-name    MyApp] \
    [--version     1.0.0] \
    [--iscc        "C:\\Program Files (x86)\\Inno Setup 6\\ISCC.exe"]
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

def run(cmd, **kw):
    print(">", " ".join(map(str, cmd)))
    subprocess.check_call(cmd, **kw)

def find_iscc(custom_path=None):
    if custom_path:
        p = Path(custom_path)
        if p.exists(): return str(p)
    auto = shutil.which("ISCC.exe")
    if auto: return auto
    # default install folder
    p = Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe")
    if p.exists(): return str(p)
    sys.exit("ERROR: ISCC.exe not found (install Inno Setup 6)")

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--app-folder", required=True,
                   help="Your Python project root (with requirements.txt)")
    p.add_argument("--iss", required=True,
                   help="Path to your Inno Setup .iss script")
    p.add_argument("--output-exe", required=True,
                   help="Where to write the final installer .exe")
    p.add_argument("--entry-file", default="core.py",
                   help="Entrypoint inside your project (default: core.py)")
    p.add_argument("--app-name", help="Name of your app (defaults to project folder name)")
    p.add_argument("--version", default="1.0.0",
                   help="Version string (default: 1.0.0)")
    p.add_argument("--iscc", help="Explicit path to ISCC.exe")
    args = p.parse_args()

    app_dir    = Path(args.app_folder).resolve()
    iss_path   = Path(args.iss).resolve()
    output_exe = Path(args.output_exe).resolve()
    output_exe.parent.mkdir(parents=True, exist_ok=True)

    if not app_dir.is_dir():
        sys.exit(f"ERROR: app-folder not found: {app_dir}")
    if not iss_path.is_file():
        sys.exit(f"ERROR: .iss file not found: {iss_path}")

    app_name = args.app_name or app_dir.name
    version  = args.version
    iscc     = find_iscc(args.iscc)

    with tempfile.TemporaryDirectory() as tmp:
        build_dir = Path(tmp) / f"{app_name}_pkg"
        # 1) run package_app.py
        run([sys.executable,
             str(Path(__file__).parent / "package_app.py"),
             str(app_dir),
             "--app-name",    app_name,
             "--entry-file",  args.entry_file,
             "--version",     version,
             "--out-dir",     str(build_dir)],
            cwd=tmp)

        if not build_dir.exists():
            sys.exit("ERROR: packaging failed (no build folder)")

        # 2) compile the .iss
        defines = [
            f"/DBuildDir={build_dir}",
            f"/DAppName={app_name}",
            f"/DAppVer={version}",
            f"/DOutName={output_exe.stem}"
        ]
        run([iscc, str(iss_path)] + defines)

    print(f"\n✓ Installer ready → {output_exe}")

if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"\n✖ Build failed (exit {e.returncode})")
