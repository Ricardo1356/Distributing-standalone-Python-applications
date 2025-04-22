# Python Application Self-Contained Installer Workflow

This project provides a workflow to package a Python application into a self-contained Windows installer using Inno Setup. The installer bundles a specific Python version, installs dependencies via pip, and creates necessary shortcuts.

## Project Structure

. ├── .gitignore  
├── build_installer.py # Script to compile the Inno Setup installer  
├── installer.iss # Inno Setup script template  
├── package_app.py # Script to prepare the application files for Inno Setup  
├── README.md # This file  
├── setup.ps1 # PowerShell script run by the installer for setup tasks  
└── (Your App Source Dir) # Directory containing your Python application code  
└── Output/ # Default directory for the final installer .exe

## Workflow Overview

1.  **Prepare Your Application:**
    *   Place your Python application code in a dedicated directory (e.g., `my_app_src`).
    *   Ensure this directory contains a `requirements.txt` file listing all dependencies.
    *   (Optional) Specify the required Python version in `requirements.txt` (e.g., `python==3.10.11`). If not specified, the default version (3.10.0) will be used by the installer's `setup.ps1`.

2.  **Run `build_installer.py`:**
    *   This is the main script to execute. It handles both packaging the application files (by calling `package_app.py`) and compiling the Inno Setup installer.
    *   **Arguments:**
        *   `--app-folder` (Required): Path to your Python project's root directory (the one containing `requirements.txt`).
        *   `--iss` (Required): Path to your Inno Setup script file (e.g., `installer.iss`).
        *   `--output-dir` (Optional): Directory where the final installer `.exe` will be placed. Defaults to `./dist`.
        *   `--entry-file` (Optional): The main Python script file within your project that should be run when the application starts. Defaults to `core.py`.
        *   `--app-name` (Optional): The name for your application. If not provided, it defaults to the name of the `--app-folder` directory.
        *   `--version` (Optional): The version string for your application (e.g., "1.2.0"). Defaults to "1.0.0".
        *   `--iscc` (Optional): Explicit path to the Inno Setup compiler executable (`ISCC.exe`). If not provided, the script will try to find it automatically (via PATH or default installation location).
    *   **Example command:**
        ```bash
        python build_installer.py --app-folder ./my_app_src --iss ./installer.iss --app-name "MyCoolApp" --version "1.2.0" --entry-file "main.py" --output-dir ./Output
        ```
    *   **Process:**
        *   The script first calls `package_app.py` functions internally to prepare a temporary staging directory containing your application code and necessary setup files (`_internal` folder with `setup.ps1`, `boot.py`, `metadata.txt`, etc.).
        *   It then invokes the Inno Setup compiler (`ISCC.exe`), passing the `--iss` file path and defining variables like `AppName`, `AppVersion`, and the path to the staging directory (`BuildDir`).
        *   The compiled installer `.exe` is placed in the specified `--output-dir`.

3.  **Test the Installer:**
    *   Run the generated installer `.exe` (e.g., `Output/MyCoolApp-1.2.0-Installer.exe`) to verify that it installs your application correctly.
    *   Check that dependencies are installed, shortcuts are created, and the application runs as expected.

4.  **Distribute the Installer:**
    *   Share the generated `.exe` file with users for installation on their systems.