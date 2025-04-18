#!/usr/bin/env python3
import os
import sys
import shutil

from metadata_generator import create_metadata
from custompth_generator import write_custom_pth
from boot_creator import create_boot_file
from installer_scripts_copier import copy_installer_scripts

def copy_app_folder(src_folder, dst_folder):
    shutil.copytree(src_folder, dst_folder)
    # Ensure __init__.py exists for proper module loading
    init_file = os.path.join(dst_folder, "__init__.py")
    if not os.path.exists(init_file):
        with open(init_file, "w", encoding="utf-8") as f:
            f.write("")
    print(f"[package_app] Copied application folder '{src_folder}' -> '{dst_folder}'")

def main():
    if len(sys.argv) != 6:
        print("Usage: package_app.py <external_app_folder> <app_name> <entry_file> <app_version> <python_version>")
        sys.exit(1)

    external_app_folder = os.path.abspath(sys.argv[1])
    app_name            = sys.argv[2]
    entry_file          = sys.argv[3]
    app_version         = sys.argv[4]
    python_version      = sys.argv[5]

    if not os.path.isdir(external_app_folder):
        print(f"[package_app] ERROR: external app folder not found: {external_app_folder}")
        sys.exit(1)

    # Determine project root (one level above SetupFiles folder)
    scripts_dir  = os.path.dirname(os.path.abspath(__file__))  # This is SetupFiles folder
    project_root = os.path.dirname(scripts_dir)
    
    # Create a persistent _temp folder in the project root
    temp_dir = os.path.join(project_root, "_temp")
    os.makedirs(temp_dir, exist_ok=True)

    # Create top-level package folder (use sanitized app_name)
    top_level_name = app_name.replace(" ", "_")
    top_level_path = os.path.join(temp_dir, top_level_name)
    if os.path.exists(top_level_path):
        shutil.rmtree(top_level_path)
    os.makedirs(top_level_path, exist_ok=True)

    # Create SetupFiles subfolder inside the package folder
    package_setup_files = os.path.join(top_level_path, "SetupFiles")
    os.makedirs(package_setup_files, exist_ok=True)

    # 1) Copy installer script (setup.ps1) into the new SetupFiles folder
    copy_installer_scripts(package_setup_files, scripts_dir)

    # 2) Generate custom_pth.txt from python_version
    pth_file = os.path.join(package_setup_files, "custom_pth.txt")
    write_custom_pth(pth_file, python_version)

    # 3) Create metadata.txt (use external app folder's basename as the app folder name inside the package)
    external_app_basename = os.path.basename(external_app_folder)
    create_metadata(package_setup_files, app_name, external_app_basename, entry_file, app_version)

    # 4) Create boot.py in SetupFiles
    create_boot_file(package_setup_files, external_app_basename, entry_file)

    # 5) Copy the external application folder into the package folder
    dst_app = os.path.join(top_level_path, external_app_basename)
    copy_app_folder(external_app_folder, dst_app)

    print(f"[package_app] Packaging done. Package folder is at: {top_level_path}")

if __name__ == "__main__":
    main()
