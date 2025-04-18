#!/usr/bin/env python3
import os
import shutil
import sys

def copy_installer_scripts(target_folder, source_folder):
    # Only copy setup.ps1
    script_name = "setup.ps1"
    src = os.path.join(source_folder, script_name)
    if os.path.isfile(src):
        shutil.copy2(src, target_folder)
        print(f"[installer_scripts_copier] Copied {script_name} to {target_folder}")
    else:
        print(f"[installer_scripts_copier] Warning: {script_name} not found in {source_folder}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: installer_scripts_copier.py <target_folder> <source_folder>")
        sys.exit(1)
    target_folder = sys.argv[1]
    source_folder = sys.argv[2]
    copy_installer_scripts(target_folder, source_folder)
