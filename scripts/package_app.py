"""
Prepares Python application files for packaging by Inno Setup.

This script takes an application source directory and organizes its content,
along with necessary helper scripts and metadata, into a staging directory.
This staging directory is then used by `build_installer.py` to create the
final Windows installer.

Key tasks performed:
- Copies application source code.
- Determines Python version from `requirements.txt` or uses a default.
- Generates `boot.py` (the application launcher).
- Generates `metadata.txt` (with application name, version, entry file, etc.).
- Generates `custom_pth.txt` (for Python's site-specific configuration).
- Copies installer helper scripts (`setup.ps1`, `setup_gui.ps1`).
- Creates a helper `setup.bat` for manual execution of `setup.ps1`.
"""
import argparse, os, re, shutil, sys
from pathlib import Path
from packaging.version import parse as parse_version

INTERNAL_SCRIPTS_DIR_NAME = "_internal"
PYTHON_ENV_DIR_NAME = "Env"  # Relative to the application's installation root
APP_LOGS_DIR_NAME = "logs"    # Relative to the application's installation root

# ───────────────────── helpers ─────────────────────
def get_python_version(req: Path) -> str:
    """Return python version from requirements.txt or 3.10.0.
    Warns if the version is below 3.9.
    """
    # Regex patterns to find Python version specifiers in requirements.txt
    formats = [
        re.compile(r"python\s*==\s*([\d.]+)", re.I),            # python==3.12.1
        re.compile(r'python\s*==\s*"([\d.]+)"', re.I),          # python=="3.12.1"
        re.compile(r'python\s*=\s*"([\d.]+)"', re.I),           # python="3.12.1"
        re.compile(r'python_version\s*=\s*"([\d.]+)"', re.I)    # python_version="3.12.1"
    ]
    
    min_supported_version = parse_version("3.9")
    default_version = "3.10.0"
    found_version_str = None

    try:
        content = req.read_text(encoding="utf-8").splitlines()
        for line in content:
            for pattern in formats:
                match = pattern.search(line)
                if match:
                    version_str = match.group(1)
                    print(f"Found Python version in requirements.txt: {version_str}")
                    found_version_str = version_str
                    
                    # Check against minimum supported version
                    parsed_found_version = parse_version(version_str)
                    if parsed_found_version < min_supported_version:
                        print(f"WARNING: The Python version {version_str} specified in requirements.txt is below the minimum recommended version {min_supported_version}.")
                        print(f"         Proceeding with version {version_str}, but compatibility issues may arise.")
                    return version_str # Return the found version
    except FileNotFoundError:
        print(f"Warning: requirements.txt not found at {req}. Using default Python version {default_version}.")
    except Exception as e:
        print(f"Warning: Error reading requirements.txt: {e}. Using default Python version {default_version}.")
    
    # Default if no version found or error occurred
    if not found_version_str:
        print(f"No Python version found in requirements.txt. Using default {default_version}")
    return default_version

def generate_custom_pth(ver: str) -> str:
    """Generates the content for a .pth file to configure Python's sys.path.

    Args:
        ver: The Python version string (e.g., "3.10.0").

    Returns:
        A string containing the .pth file content.
    """
    parts = ver.split(".")
    base  = "python" + parts[0] + parts[1] if len(parts) >= 2 else "python" + ver.replace(".","")
    return f"{base}.zip\nLib\n.\nimport site\n"

def create_boot_py(internal_scripts_dir: Path, app_pkg_name: str, entry_module_file: str) -> None:
    """
    Creates the boot.py script inside the internal scripts directory.
    The generated boot.py will use global constants for Env and logs directories.
    """
    
    module_path_str = str(Path(entry_module_file.replace("\\", ".").replace("/", ".")).with_suffix(""))

    # These constants define standard sub-directory names within the installed application.
    # They are embedded into the boot.py template.
    boot_template = """#!/usr/bin/env python3
import sys
import os
import runpy
import datetime
import traceback

# --- Directory Name Constants (from package_app.py) ---
# These are embedded by package_app.py when creating this boot script.
PYTHON_ENV_DIR_NAME_CONST = "{python_env_dir_placeholder}"
APP_LOGS_DIR_NAME_CONST = "{app_logs_dir_placeholder}"

# --- Globals for error reporting (values set by package_app.py via .format()) ---
_app_pkg_name_for_boot_template = "{app_pkg_placeholder}"
_entry_module_for_boot_template = "{module_path_placeholder}"
_install_root_for_boot = None # Will be set in try block

try:
    script_dir = os.path.dirname(__file__)
    _install_root_for_boot = os.path.abspath(os.path.join(script_dir, ".."))
    
    # Path to the application's code directory (e.g., <install_root>/AppName)
    app_code_path = os.path.join(_install_root_for_boot, _app_pkg_name_for_boot_template)
    # Path to the bundled Python environment (e.g., <install_root>/Env)
    env_path = os.path.join(_install_root_for_boot, PYTHON_ENV_DIR_NAME_CONST)
    site_packages_path = os.path.join(env_path, "Lib", "site-packages")

    paths_to_add = [_install_root_for_boot, app_code_path, site_packages_path, env_path]
    for p_idx, p_val in enumerate(paths_to_add):
        if os.path.exists(p_val) and p_val not in sys.path:
            sys.path.insert(p_idx, p_val)

    os.environ[f"{{_app_pkg_name_for_boot_template.upper()}}_INSTALL_ROOT"] = _install_root_for_boot # Escaped
    runpy.run_module(f"{{_app_pkg_name_for_boot_template}}.{{_entry_module_for_boot_template}}", run_name="__main__") # Escaped

except Exception as e:
    timestamp_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    error_type = type(e).__name__
    error_message_detail = str(e)
    full_traceback = traceback.format_exc()

    log_header = f"--- APPLICATION BOOT ERROR LOG: {{_app_pkg_name_for_boot_template}} ---" # Escaped
    log_content = f\"\"\"{{{{log_header}}}}  # Double escaped
Timestamp: {{timestamp_str}}
Python Version: {{sys.version.split()[0]}} ({{sys.executable}})
OS: {{sys.platform}}
Install Root: {{_install_root_for_boot if _install_root_for_boot else 'Unknown'}}
App Package: {{_app_pkg_name_for_boot_template}}
Entry Module: {{_entry_module_for_boot_template}}

Error Type: {{error_type}}
Error Message: {{error_message_detail}}

Full Traceback:
{{full_traceback}}
--------------------------------------------------
\"\"\"
    log_file_path_str = "Unknown"

    if _install_root_for_boot:
        # Log directory (e.g., <install_root>/logs)
        log_dir = os.path.join(_install_root_for_boot, APP_LOGS_DIR_NAME_CONST)
        try:
            os.makedirs(log_dir, exist_ok=True)
            log_file_path_str = os.path.join(log_dir, f"{{_app_pkg_name_for_boot_template}}_boot_error.log") # Escaped
        except Exception: 
            temp_dir = os.environ.get('TEMP', os.path.expanduser("~"))
            os.makedirs(temp_dir, exist_ok=True) 
            log_file_path_str = os.path.join(temp_dir, f"{{_app_pkg_name_for_boot_template}}_boot_error_fallback.log") # Escaped
    else: 
        temp_dir = os.environ.get('TEMP', os.path.expanduser("~"))
        os.makedirs(temp_dir, exist_ok=True)
        log_file_path_str = os.path.join(temp_dir, f"{{_app_pkg_name_for_boot_template}}_boot_error_fallback.log") # Escaped
        
    logged_to_file_msg = f"Details have been logged to: {{log_file_path_str}}" # Escaped
    try:
        with open(log_file_path_str, 'a', encoding='utf-8') as f:
            f.write(log_content)
    except Exception as log_write_e:
        logged_to_file_msg = f"Failed to write to log file '{{log_file_path_str}}'. Error: {{log_write_e}}" # Escaped
        print(f"FATAL: Could not write to log file '{{log_file_path_str}}': {{log_write_e}}", file=sys.stderr) # Escaped

    user_error_title = f"{{_app_pkg_name_for_boot_template}} - Application Startup Error" # Escaped
    user_error_summary = f\"\"\"A critical error occurred while starting {{_app_pkg_name_for_boot_template}}.

Error: {{error_type}} - {{error_message_detail}}

{{logged_to_file_msg}}

Please check the log file for a detailed traceback and report this issue.\"\"\"

    print(f"FATAL ERROR in {{_app_pkg_name_for_boot_template}}: {{error_type}} - {{error_message_detail}}. {{logged_to_file_msg}}", file=sys.stderr) # Escaped

    if sys.platform == 'win32':
        try:
            import ctypes
            ctypes.windll.user32.MessageBoxW(None, user_error_summary, user_error_title, 0x10 | 0x0)
        except Exception as mb_e:
            print(f"\\nCould not display Windows error message box: {{mb_e}}." # Escaped
                  f" Full error details printed below:", file=sys.stderr) # Escaped
            print(log_content, file=sys.stderr)
    else:
        print(f"\\nFull error details:", file=sys.stderr)
        print(log_content, file=sys.stderr)
        
    sys.exit(1)
"""

    boot_script_content = boot_template.format(
        app_pkg_placeholder=app_pkg_name,
        module_path_placeholder=module_path_str,
        python_env_dir_placeholder=PYTHON_ENV_DIR_NAME, # Pass constant
        app_logs_dir_placeholder=APP_LOGS_DIR_NAME       # Pass constant
    )

    (internal_scripts_dir / "boot.py").write_text(boot_script_content, encoding="utf-8")
    
def ensure_pkg_tree(root: Path) -> None:
    """Ensures that all directories containing .py files within the given root
    are Python packages by creating an __init__.py file if one doesn't exist.

    Args:
        root: The root directory to scan.
    """
    for cur,_,files in os.walk(root):
        if any(f.endswith(".py") for f in files):
            ip = Path(cur, "__init__.py")
            if not ip.exists(): ip.touch()

# ───────────────────── main build ─────────────────────
def build(out_dir: Path,
          src_dir: Path,
          app_name: str, 
          entry_file: str,
          version: str) -> None:
    """
    Builds the application package into out_dir.

    The structure will be:
    <out_dir>/
        _internal/  (contains setup.ps1, metadata.txt, boot.py, custom_pth.txt, setup.bat)
        <app_name>/ (contains the application source code)
    """
    print(f"Packaging {app_name} v{version} from {src_dir} into {out_dir}")

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True) # Ensure out_dir itself exists

    internal_dir = out_dir / INTERNAL_SCRIPTS_DIR_NAME
    internal_dir.mkdir(exist_ok=True)

    # Copy installer helper scripts (e.g., setup.ps1) from the directory where package_app.py resides.
    current_script_dir = Path(__file__).parent
    # setup_gui.ps1 is included here as it was in the original project structure.
    # If it's not used by your setup.ps1 or Inno Setup script, it can be removed from this list.
    for fname in ("setup.ps1", "setup_gui.ps1"):
        source_file = current_script_dir / fname
        if source_file.is_file():
            shutil.copy2(source_file, internal_dir / fname)
        else:
            print(f"Warning: Script '{fname}' not found in '{current_script_dir}', not copied.")

    pyver = get_python_version(src_dir / "requirements.txt")
    
    (internal_dir / "metadata.txt").write_text(
        f"AppName={app_name}\n"
        f"AppFolder={app_name}\n" # App's code will be in a subfolder named after the app_name within the install root
        f"EntryFile={entry_file}\n"
        f"Version={version}\n"
        f"PythonVersion={pyver}\n",
        encoding="utf-8")
        
    create_boot_py(internal_dir, app_name, entry_file)
    
    (internal_dir / "custom_pth.txt").write_text(generate_custom_pth(pyver), "ascii")

    # Copy the application's source code tree.
    app_code_destination_dir = out_dir / app_name
    if app_code_destination_dir.exists():
        shutil.rmtree(app_code_destination_dir)
    shutil.copytree(src_dir, app_code_destination_dir, ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '.git', '.vscode'))
    ensure_pkg_tree(app_code_destination_dir) # Ensure all subdirectories are importable packages.

    # Create a helper batch file for manually testing setup.ps1.
    (internal_dir / "setup.bat").write_text(
        '@echo off\r\n'
        f'echo Running setup from %~dp0setup.ps1\r\n'
        f'echo Installation target (parent of _internal) will be %~dp0..\\\r\n'
        # Ensure InstallPath is quoted and ends with a backslash if it's a directory
        f'powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0setup.ps1" -InstallPath "%~dp0..\\"\r\n'
        'echo Setup script finished. Press any key to exit.\r\n'
        'pause\r\n', 
        encoding="ascii")

# ───────────────────── CLI ─────────────────────
def main() -> None:
    """Command-line interface for the application packager."""
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
    # Basic error handling for the CLI entry point
    try:
        main()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
