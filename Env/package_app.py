#!/usr/bin/env python3
"""
package_app.py
Build a portable ZIP installer for any Python project that ships with
PowerShell‑based setup logic (setup.ps1) and uses an embedded CPython runtime.

Key features added in this version
----------------------------------
1.  A smarter bootstrap (SetupFiles/boot.py) that puts *both* the install
    directory **and** the real application package directory on sys.path.
    That lets projects use either package‑relative or project‑root absolute
    imports without modification.
2.  `ensure_package_tree()` – walks the copied application tree and drops an
    empty __init__.py into any folder that lacks one, so everything is a valid
    Python package.
"""

import argparse
import os
import re
import shutil
import tempfile
import zipfile


# ---------------------------------------------------------------------------
# Helper #1 – extract python==X.Y.Z from requirements.txt (default 3.10.0)
# ---------------------------------------------------------------------------
def get_python_version(req_file: str) -> str:
    version = "3.10.0"
    try:
        with open(req_file, "r", encoding="utf-8") as f:
            for line in f:
                m = re.search(r"python==([\d.]+)", line, re.I)
                if m:
                    version = m.group(1)
                    break
    except (OSError, UnicodeDecodeError):
        pass
    return version


# ---------------------------------------------------------------------------
# Helper #2 – produce the content for a custom *_pth* file
# ---------------------------------------------------------------------------
def generate_custom_pth(python_version: str) -> str:
    parts = python_version.split(".")
    base = "python" + parts[0] + parts[1] if len(parts) >= 2 else \
           "python" + python_version.replace(".", "")
    return f"{base}.zip\nLib\n.\nimport site\n"


# ---------------------------------------------------------------------------
# Helper #3 – create SetupFiles/boot.py (***NEW*** version)
# ---------------------------------------------------------------------------
def create_boot_file(target_folder: str,
                     app_folder_name: str,
                     entry_file: str) -> None:
    """
    Build a bootstrap that:
      • adds both the install folder and the app package folder to sys.path
      • converts an entry file like “core.py” or “sub/launch.py” to a module
        path and executes it with runpy.run_module()
    """
    entry_module = os.path.splitext(
        entry_file.replace("\\", ".").replace("/", ".")
    )[0]

    boot_content = f'''import sys, os, runpy

# Installation root (…/MyApp)
install_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Real application package folder (…/MyApp/{app_folder_name})
app_dir = os.path.join(install_dir, "{app_folder_name}")

for _p in (install_dir, app_dir):
    if _p not in sys.path:
        sys.path.insert(0, _p)

runpy.run_module("{app_folder_name}.{entry_module}", run_name="__main__")
'''

    os.makedirs(target_folder, exist_ok=True)
    with open(os.path.join(target_folder, "boot.py"),
              "w", encoding="utf-8") as f:
        f.write(boot_content)


# ---------------------------------------------------------------------------
# Helper #4 – copy installer scripts if present
# ---------------------------------------------------------------------------
def copy_installer_scripts(dest: str, src_dir: str) -> None:
    for fname in ("setup.ps1", "setup_gui.ps1"):
        src = os.path.join(src_dir, fname)
        if os.path.isfile(src):
            shutil.copy2(src, dest)


# ---------------------------------------------------------------------------
# Helper #5 – ensure every directory under *root* is a package
# ---------------------------------------------------------------------------
def ensure_package_tree(root: str) -> None:
    for cur_dir, dirs, files in os.walk(root):
        if any(f.endswith(".py") for f in files):
            init_path = os.path.join(cur_dir, "__init__.py")
            if not os.path.exists(init_path):
                open(init_path, "w", encoding="utf-8").close()


# ---------------------------------------------------------------------------
# Build the temporary folder layout
# ---------------------------------------------------------------------------
def create_package_structure(temp_dir: str,
                             top_level: str,
                             app_folder: str,
                             packaging_script_dir: str,
                             custom_pth_content: str,
                             app_name: str,
                             entry_file: str,
                             app_version: str) -> str:

    top_path = os.path.join(temp_dir, top_level)
    setup_path = os.path.join(top_path, "SetupFiles")
    os.makedirs(setup_path, exist_ok=True)

    # 1. copy installer scripts next to boot.py
    copy_installer_scripts(setup_path, packaging_script_dir)

    # 2. custom_pth.txt
    with open(os.path.join(setup_path, "custom_pth.txt"),
              "w", encoding="ascii") as f:
        f.write(custom_pth_content)

    # 3. metadata.txt
    app_basename = os.path.basename(os.path.abspath(app_folder))
    with open(os.path.join(setup_path, "metadata.txt"),
              "w", encoding="utf-8") as f:
        f.write(f"AppName={app_name}\n")
        f.write(f"AppFolder={app_basename}\n")
        f.write(f"EntryFile={entry_file}\n")
        f.write(f"Version={app_version}\n")

    # 4. boot.py
    create_boot_file(setup_path, app_basename, entry_file)

    # 5. copy the application tree
    dest_app_path = os.path.join(top_path, app_basename)
    shutil.copytree(app_folder, dest_app_path)

    # 6. be sure every folder is a package
    ensure_package_tree(dest_app_path)

    # 7. setup.bat at top level (re‑invokes PowerShell installer)
    with open(os.path.join(top_path, "setup.bat"),
              "w", encoding="ascii") as f:
        f.write('@echo off\r\n'
                'powershell.exe -ExecutionPolicy Bypass -NoProfile '
                '-File "%~dp0\\SetupFiles\\setup.ps1"\r\n'
                'pause\r\n')

    return top_path


# ---------------------------------------------------------------------------
# Helper #7 – zip it up (keep the top‑level folder)
# ---------------------------------------------------------------------------
def zip_directory(source_dir: str, output_zip: str) -> None:
    parent = os.path.dirname(source_dir)
    with zipfile.ZipFile(output_zip, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(source_dir):
            for fname in files:
                abs_f = os.path.join(root, fname)
                rel = os.path.relpath(abs_f, parent)
                zf.write(abs_f, rel)
    print(f"Created {output_zip}")


# ---------------------------------------------------------------------------
# Main CLI
# ---------------------------------------------------------------------------
def main() -> None:
    p = argparse.ArgumentParser(
        description="Package a Python application with an installer and "
                    "embedded‑Python bootstrap into a single ZIP."
    )
    p.add_argument("app_folder",
                   help="Path to the project folder (must have requirements.txt)")
    p.add_argument("-n", "--name",
                   default="python_app_package.zip",
                   help="Output ZIP filename (default: python_app_package.zip)")
    p.add_argument("--app-name", default="MyApp",
                   help="Logical/marketing name (default: MyApp)")
    p.add_argument("--entry-file", default="core.py",
                   help="Entry script path inside the project (default: core.py)")
    p.add_argument("--version", default="1.0.0",
                   help="App semantic version (default: 1.0.0)")
    args = p.parse_args()

    app_folder = os.path.abspath(args.app_folder)
    if not os.path.isdir(app_folder):
        raise SystemExit(f"ERROR: not a directory: {app_folder}")

    req_file = os.path.join(app_folder, "requirements.txt")
    if not os.path.isfile(req_file):
        raise SystemExit("ERROR: requirements.txt missing in project folder")

    py_ver = get_python_version(req_file)
    custom_pth = generate_custom_pth(py_ver)
    print(f"Python runtime required: {py_ver}")

    zip_name = args.name if args.name.lower().endswith(".zip") else f"{args.name}.zip"
    top_level_folder = os.path.splitext(os.path.basename(zip_name))[0]
    script_dir = os.path.dirname(os.path.abspath(__file__))

    with tempfile.TemporaryDirectory() as tmp:
        built_path = create_package_structure(
            tmp,
            top_level_folder,
            app_folder,
            script_dir,
            custom_pth,
            app_name=args.app_name,
            entry_file=args.entry_file,
            app_version=args.version
        )
        out_zip = os.path.join(script_dir, zip_name)
        zip_directory(built_path, out_zip)

    print("Packaging complete.")


if __name__ == "__main__":
    main()
