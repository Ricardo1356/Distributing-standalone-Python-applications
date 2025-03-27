import os
import re
import zipfile
import argparse
import tempfile
import shutil

def get_python_version(req_file):
    """Reads requirements.txt for 'python==X.Y.Z' (defaults to 3.10.0)."""
    version = "3.10.0"
    try:
        with open(req_file, "r", encoding="utf-8") as f:
            for line in f:
                match = re.search(r"python==([\d\.]+)", line, re.IGNORECASE)
                if match:
                    version = match.group(1)
                    break
    except Exception as e:
        print(f"Error reading {req_file}: {e}")
    return version

def generate_custom_pth(python_version):
    """Generates the custom _pth file content."""
    parts = python_version.split(".")
    if len(parts) >= 2:
        base = "python" + parts[0] + parts[1]
    else:
        base = "python" + python_version.replace(".", "")
    content = f"{base}.zip\nLib\n.\nimport site\n"
    return content

def create_boot_file(target_folder, app_folder_name, entry_file):
    """
    Creates boot.py in the target folder.
    This bootstrap script adjusts sys.path to include the parent folder
    (the installation folder) so that the application package is found,
    and then runs the entry module.
    """
    boot_path = os.path.join(target_folder, "boot.py")
    entry_module = os.path.splitext(entry_file)[0]
    boot_content = f'''import sys, os, runpy

# Set install_dir to the parent of this file (i.e., the installation folder).s
install_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if install_dir not in sys.path:
    sys.path.insert(0, install_dir)

# Run the entry module using runpy.
runpy.run_module("{app_folder_name}.{entry_module}", run_name="__main__")
'''
    with open(boot_path, "w", encoding="utf-8") as f:
        f.write(boot_content)

def copy_installer_scripts(target_folder, package_dir):
    """
    Copies installer scripts (setup.ps1 and setup_gui.ps1, if present) from package_dir 
    into the target_folder.
    """
    installers = ["setup.ps1", "setup_gui.ps1"]
    for inst in installers:
        src = os.path.join(package_dir, inst)
        if os.path.isfile(src):
            shutil.copy2(src, target_folder)
        else:
            print(f"Warning: {inst} not found in {package_dir}")

def create_package_structure(temp_dir, top_level, app_folder, package_dir,
                             custom_pth_content, app_name, entry_file, app_version):
    """
    Creates a folder structure like:
    
      temp_dir/
         <top_level>/          <-- This folder will be named as your app (e.g., "Test GUI")
             setup.bat        <-- Double-clickable batch file
             SetupFiles/      <-- Contains installer files
                 boot.py
                 custom_pth.txt
                 metadata.txt
                 setup.ps1
                 setup_gui.ps1   (if exists)
             <app_folder>/    <-- The entire application folder copied over
    """
    top_level_path = os.path.join(temp_dir, top_level)
    os.makedirs(top_level_path, exist_ok=True)
    
    # Create subfolder for installer files.
    setup_folder = os.path.join(top_level_path, "SetupFiles")
    os.makedirs(setup_folder, exist_ok=True)
    
    # Copy installer scripts (setup.ps1, setup_gui.ps1) from package_dir to SetupFiles.
    copy_installer_scripts(setup_folder, package_dir)
    
    # Write custom_pth.txt into SetupFiles.
    custom_pth_path = os.path.join(setup_folder, "custom_pth.txt")
    with open(custom_pth_path, "w", encoding="ascii") as f:
        f.write(custom_pth_content)
    
    # Write metadata.txt into SetupFiles.
    app_basename = os.path.basename(os.path.abspath(app_folder))
    metadata_path = os.path.join(setup_folder, "metadata.txt")
    with open(metadata_path, "w", encoding="utf-8") as f:
        f.write(f"AppName={app_name}\n")
        f.write(f"AppFolder={app_basename}\n")
        f.write(f"EntryFile={entry_file}\n")
        f.write(f"Version={app_version}\n")
    
    # Create boot.py in SetupFiles.
    create_boot_file(setup_folder, app_basename, entry_file)
    
    # Copy the entire application folder into top_level.
    dest_app_path = os.path.join(top_level_path, app_basename)
    shutil.copytree(app_folder, dest_app_path)
    
    # Patch the application folder: add __init__.py if missing.
    init_file = os.path.join(dest_app_path, "__init__.py")
    if not os.path.exists(init_file):
        with open(init_file, "w", encoding="utf-8") as f:
            f.write("")
    
    # Create setup.bat in the top_level folder.
    setup_bat_path = os.path.join(top_level_path, "setup.bat")
    bat_content = (
        '@echo off\r\n'
        'powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0\\SetupFiles\\setup.ps1"\r\n'
        'pause\r\n'
    )
    with open(setup_bat_path, "w", encoding="ascii") as f:
        f.write(bat_content)
    
    return top_level_path

def zip_directory(source_dir, output_zip):
    """
    Zips the contents of source_dir into output_zip,
    preserving source_dir as the top-level folder.
    """
    parent_of_source = os.path.dirname(source_dir)
    with zipfile.ZipFile(output_zip, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(source_dir):
            for file in files:
                abs_file = os.path.join(root, file)
                rel_path = os.path.relpath(abs_file, parent_of_source)
                zipf.write(abs_file, rel_path)
    print(f"Packaged project into {output_zip}")

def main():
    parser = argparse.ArgumentParser(
        description="Package the application with installer files, metadata, a custom _pth file, and a bootstrap script into a ZIP archive."
    )
    parser.add_argument("app_folder", help="Path to the application folder (must contain requirements.txt)")
    parser.add_argument(
        "-n", "--name",
        default="python_app_package.zip",
        help="Output ZIP file name (default: python_app_package.zip)"
    )
    parser.add_argument(
        "--app-name",
        default="MyApp",
        help="Logical name of the application (default: MyApp)"
    )
    parser.add_argument(
        "--entry-file",
        default="main.py",
        help="Relative path (within your app_folder) of the script to run (default: main.py)"
    )
    parser.add_argument(
        "--version",
        default="1.0.0",
        help="Version of the application (default: 1.0.0)"
    )

    args = parser.parse_args()

    # Validate the app folder.
    app_folder = os.path.abspath(args.app_folder)
    if not os.path.isdir(app_folder):
        print(f"Error: The specified application folder does not exist: {app_folder}")
        return

    # Validate requirements.txt exists.
    req_file = os.path.join(app_folder, "requirements.txt")
    if not os.path.isfile(req_file):
        print(f"Error: requirements.txt not found in: {app_folder}")
        return

    # Determine Python version from requirements.txt.
    python_version = get_python_version(req_file)
    print(f"Determined Python version: {python_version}")

    # Generate custom _pth file content.
    custom_pth_content = generate_custom_pth(python_version)
    print("Generated custom _pth content:")
    print(custom_pth_content)

    # Get the directory of this packaging script.
    package_dir = os.path.dirname(os.path.abspath(__file__))

    # Final ZIP name.
    zip_name = args.name if args.name.lower().endswith(".zip") else args.name + ".zip"
    top_level = os.path.splitext(os.path.basename(zip_name))[0]

    with tempfile.TemporaryDirectory() as temp_dir:
        package_structure_path = create_package_structure(
            temp_dir,
            top_level,
            app_folder,
            package_dir,
            custom_pth_content,
            app_name=args.app_name,
            entry_file=args.entry_file,
            app_version=args.version
        )
        output_zip = os.path.join(package_dir, zip_name)
        zip_directory(package_structure_path, output_zip)

    print("Packaging complete.")

if __name__ == "__main__":
    main()
