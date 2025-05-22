import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
import json  # For JSON configuration

def run(cmd, **kw):
    print(">", " ".join(map(str, cmd)))
    subprocess.check_call(cmd, **kw)

def find_iscc(custom_path=None):
    if custom_path:
        p = Path(custom_path)
        if p.exists(): return str(p)
    auto = shutil.which("ISCC.exe")
    if auto: return auto
    # default ISCC install folder
    p = Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe")
    if p.exists(): return str(p)
    sys.exit("ERROR: ISCC.exe not found (install Inno Setup 6)")

def load_config():
    """Load build configuration from the JSON file"""
    config_path = Path(__file__).parent / "build_config.json"
    if not config_path.exists():
        sys.exit(f"ERROR: Configuration file not found: {config_path}")
        
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        print(f"Loaded configuration from {config_path}")
        return config
    except Exception as e:
        sys.exit(f"ERROR: Failed to load config file {config_path}: {e}")

def main():
    # Load configuration from JSON file
    config = load_config()
    print("Using configuration with these values:")
    print(f"  App name: {config.get('appName', 'Not specified')}")
    print(f"  Version: {config.get('appVersion', 'Not specified')}")
    print(f"  App folder: {config.get('appFolder', 'Not specified')}")
    
    # Set defaults for any missing values
    if 'appVersion' not in config:
        config['appVersion'] = "1.0.0"
    if 'entryFile' not in config:
        config['entryFile'] = "core.py"
    if 'outputDir' not in config:
        config['outputDir'] = "./dist"

    # Validate required configuration values
    if not config.get('appFolder'):
        sys.exit("ERROR: No appFolder specified in configuration file.")
    if not config.get('issPath'):
        sys.exit("ERROR: No issPath specified in configuration file.")

    # Resolve paths relative to script directory if needed
    script_dir = Path(__file__).parent
    
    app_dir = Path(config['appFolder'])
    if not app_dir.is_absolute():
        app_dir = (script_dir / app_dir).resolve()
    
    iss_path = Path(config['issPath'])
    if not iss_path.is_absolute():
        iss_path = (script_dir / iss_path).resolve()
    
    output_dir = Path(config['outputDir'])
    if not output_dir.is_absolute():
        output_dir = (script_dir / output_dir).resolve()
    
    output_dir.mkdir(parents=True, exist_ok=True)  # Ensure output directory exists

    # Validate paths
    if not app_dir.is_dir():
        sys.exit(f"ERROR: App folder not found: {app_dir}")
    if not iss_path.is_file():
        sys.exit(f"ERROR: .iss file not found: {iss_path}")

    app_name = config['appName'] or app_dir.name
    version = config['appVersion']
    iscc = find_iscc(config.get('isccPath'))

    # Construct the expected final output path based on .iss OutputBaseFilename
    # Assumes OutputBaseFilename={#AppName}-{#AppVersion}
    final_exe_name = f"{app_name}-{version}.exe"
    final_exe_path = output_dir / final_exe_name

    with tempfile.TemporaryDirectory() as tmp:
        build_dir = Path(tmp) / f"{app_name}_pkg"
        # 1) run package_app.py
        run([sys.executable,
             str(Path(__file__).parent / "package_app.py"),
             str(app_dir),
             "--app-name",    app_name,
             "--entry-file",  config['entryFile'],
             "--version",     version,
             "--out-dir",     str(build_dir)],
            cwd=tmp)

        if not build_dir.exists():
            sys.exit("ERROR: packaging failed (no build folder)")

        # 2) compile the .iss
        # Pass AppName and AppVersion for the .iss script
        # Use /O to specify the output *directory* for ISCC
        defines = [
            f"/DBuildDir={build_dir}",
            f"/DAppName={app_name}",
            f"/DAppVersion={version}"
        ]
        iscc_cmd = [iscc, f"/O{output_dir}", str(iss_path)] + defines
        run(iscc_cmd)

    print(f"\n✓ Installer ready → {final_exe_path}")

if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"\n✖ Build failed (exit {e.returncode})")
    except Exception as e:
        sys.exit(f"\n✖ Build failed: {e}")