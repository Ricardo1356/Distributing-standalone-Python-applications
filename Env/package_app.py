#!/usr/bin/env python3
"""
package_app.py   –   build a *folder* ready for ISCC
┌────────────────────────────────────────────────────────────┐
│  <out‑dir>/                                               │
│     SetupFiles/   boot.py  metadata.txt  custom_pth.txt   │
│     setup.bat                                              │
│     <YourProject>/  (your whole source tree, patched)      │
└────────────────────────────────────────────────────────────┘
No ZIP is produced; ISCC can point straight at <out‑dir>.
"""

import argparse, os, re, shutil, sys
from pathlib import Path

# ───────────────────── helpers ─────────────────────
def get_python_version(req: Path) -> str:
    """Return python version from requirements.txt or 3.10.0."""
    # Check for all possible formats
    formats = [
        re.compile(r"python\s*==\s*([\d.]+)", re.I),            # python==3.12.1
        re.compile(r'python\s*==\s*"([\d.]+)"', re.I),          # python=="3.12.1"
        re.compile(r'python\s*=\s*"([\d.]+)"', re.I),           # python="3.12.1"
        re.compile(r'python_version\s*=\s*"([\d.]+)"', re.I)    # python_version="3.12.1"
    ]
    
    try:
        content = req.read_text(encoding="utf-8").splitlines()
        for line in content:
            for pattern in formats:
                match = pattern.search(line)
                if match:
                    version = match.group(1)
                    print(f"Found Python version in requirements.txt: {version}")
                    return version
    except Exception as e:
        print(f"Warning: Error reading requirements.txt: {e}")
    
    # Default if no version found
    print("No Python version found in requirements.txt. Using default 3.10.0")
    return "3.10.0"

def generate_custom_pth(ver: str) -> str:
    parts = ver.split(".")
    base  = "python" + parts[0] + parts[1] if len(parts) >= 2 else "python" + ver.replace(".","")
    return f"{base}.zip\nLib\n.\nimport site\n"

def create_boot_py(setup_dir: Path, app_pkg: str, entry: str) -> None:
    mod = Path(entry.replace("\\", ".").replace("/", ".")).with_suffix("")
    boot = f'''import sys, os, runpy
inst = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
app  = os.path.join(inst, "{app_pkg}")
for p in (inst, app):
    sys.path.insert(0, p) if p not in sys.path else None
runpy.run_module("{app_pkg}.{mod}", run_name="__main__")
'''
    (setup_dir/"boot.py").write_text(boot, encoding="utf-8")
    
def create_boot_py(setup_dir: Path, app_pkg: str, entry: str) -> None:
    """Creates the boot.py script inside SetupFiles."""
    mod = Path(entry.replace("\\", ".").replace("/", ".")).with_suffix("")
    # boot.py is in SetupFiles. It needs to find the install root ('..')
    # and the app code ('../<app_pkg>') and env ('../Env') relative to itself.
    boot = f'''import sys, os, runpy
try:
    script_dir = os.path.dirname(__file__)
    install_root = os.path.abspath(os.path.join(script_dir, ".."))
    app_code_path = os.path.join(install_root, "{app_pkg}")
    env_path = os.path.join(install_root, "Env") # Changed to Env
    site_packages = os.path.join(env_path, "Lib", "site-packages")

    paths_to_add = [app_code_path, site_packages, env_path, install_root]
    for p in reversed(paths_to_add): # Reverse to prepend in the desired order
        if os.path.exists(p) and p not in sys.path:
            sys.path.insert(0, p)

    os.environ["MYAPP_INSTALL_ROOT"] = install_root # Example variable name

    runpy.run_module("{app_pkg}.{mod}", run_name="__main__")

except Exception as e:
    print(f"FATAL ERROR: Failed to start application: {{e}}", file=sys.stderr)
    # Optionally, write to a log file in a known location like %TEMP%
    # temp_log = os.path.join(os.environ.get('TEMP', '.'), 'myapp_boot_error.log')
    # with open(temp_log, 'a', encoding='utf-8') as f:
    #     import traceback, datetime
    #     f.write(f"Timestamp: {{datetime.datetime.now()}}\\n")
    #     f.write(traceback.format_exc() + '\\n')
    sys.exit(1)
'''
    (setup_dir/"boot.py").write_text(boot, encoding="utf-8")

def ensure_pkg_tree(root: Path) -> None:
    for cur,_,files in os.walk(root):
        if any(f.endswith(".py") for f in files):
            ip = Path(cur, "__init__.py")
            if not ip.exists(): ip.touch()

# ───────────────────── main build ─────────────────────
def build(out_dir: Path,
          src_dir: Path,
          app_name: str, # This is the name we want for the app folder
          entry_file: str,
          version: str) -> None:

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    setup_dir = out_dir / "SetupFiles"
    setup_dir.mkdir()

    # 1  copy installer scripts
    here = Path(__file__).parent
    for fname in ("setup.ps1", "setup_gui.ps1"): # Add other setup files if needed
        f = here / fname
        if f.is_file():
            shutil.copy2(f, setup_dir)

    # Get Python version before metadata creation
    pyver = get_python_version(src_dir/"requirements.txt")
    
    # 2  metadata & boot with Python version included
    (setup_dir/"metadata.txt").write_text(
        f"AppName={app_name}\n"
        f"AppFolder={app_name}\n"
        f"EntryFile={entry_file}\n"
        f"Version={version}\n"
        f"PythonVersion={pyver}\n",
        encoding="utf-8")
        
    create_boot_py(setup_dir, app_name, entry_file)
    
    # 3  custom_pth.txt (no change to this part)
    (setup_dir / "custom_pth.txt").write_text(generate_custom_pth(pyver), "ascii")

    # 4  copy project tree into the correctly named folder
    app_code_dest = out_dir / app_name # Use app_name for the destination folder
    shutil.copytree(src_dir, app_code_dest, ignore=shutil.ignore_patterns('__pycache__', '*.pyc')) # Copy to app_name folder
    ensure_pkg_tree(app_code_dest) # Ensure __init__.py in the copied code

    # 5  helper setup.bat (Place inside SetupFiles)
    (setup_dir/"setup.bat").write_text(
        '@echo off\r\n'
        'powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0\\setup.ps1" -InstallPath "%~dp0\\.."\r\n'
        'pause\r\n', "ascii")

    print(f"✓ Build folder ready → {out_dir}")

# ───────────────────── CLI ─────────────────────
def main() -> None:
    ap = argparse.ArgumentParser(description="Create build folder for ISCC.")
    ap.add_argument("app_folder", help="Path to project with requirements.txt")
    ap.add_argument("--app-name",   default=None, help="Default: folder name")
    ap.add_argument("--entry-file", default="core.py")
    ap.add_argument("--version",    default="1.0.0")
    ap.add_argument("--out-dir",
                    help="Where to place the build folder "
                         "(default: _temp/<AppName>_pkg beside script)")
    args = ap.parse_args()

    src = Path(args.app_folder).resolve()
    if not src.is_dir():
        sys.exit("ERROR: app_folder not found")

    out_base = Path(args.out_dir) if args.out_dir else \
               Path("_temp", f"{args.app_name or src.name}_pkg")
    build(out_base.resolve(), src,
          args.app_name or src.name, args.entry_file, args.version)

if __name__ == "__main__":
    main()
