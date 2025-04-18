#!/usr/bin/env python3
import os
import sys

def create_boot_file(target_folder, app_folder, entry_file):
    boot_path = os.path.join(target_folder, "boot.py")
    entry_module = os.path.splitext(entry_file)[0]
    boot_content = f'''import sys, os, runpy

# Set install_dir to the parent of this file.
install_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if install_dir not in sys.path:
    sys.path.insert(0, install_dir)

# Run the entry module using runpy.
runpy.run_module("{os.path.basename(os.path.abspath(app_folder))}.{entry_module}", run_name="__main__")
'''
    with open(boot_path, "w", encoding="utf-8") as f:
        f.write(boot_content)
    print(f"Created boot.py at {boot_path}")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: boot_creator.py <target_folder> <app_folder> <entry_file>")
        sys.exit(1)
    target_folder = sys.argv[1]
    app_folder = sys.argv[2]
    entry_file = sys.argv[3]
    create_boot_file(target_folder, app_folder, entry_file)
