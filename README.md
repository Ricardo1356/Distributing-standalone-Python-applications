# Distributing standalone Python applications
## 1. Introduction

This project offers a solution for packaging Python applications into Windows installers. The key advantage is that **end-users do not need to have Python pre-installed on their systems** to run the packaged application. The installer handles the provisioning of the necessary Python runtime by downloading it during the setup process if it's not already present in the target installation directory. This ensures a smooth, user-friendly setup experience, all without requiring administrative privileges. The system uses Inno Setup for the installer shell and PowerShell for the detailed, on-demand Python environment setup and application deployment.

## 2. Project Structure

```
.
├── README.md                   # This guide
├── example_application/        # Sample Python application
│   ├── core.py
│   ├── requirements.txt
│   ├── logic/api.py
│   └── ui/layout.py
├── scripts/                    # Scripts for packaging and installation
│   ├── installer.iss           # Inno Setup script template
│   ├── setup.ps1               # PowerShell setup script (executed by installer)
│   ├── package_app.py          # Python script to prepare application files
│   └── build_installer.py      # Python script to compile the Inno Setup installer
└── UML/                        # System design diagrams (PlantUML)
    ├── activity_workflow.plantuml
    ├── component_dev.plantuml
    ├── component_user.plantuml
    └── sequence_setup.plantuml
```

## 3. Prerequisites for Building

*   **Python**: To run `package_app.py` and `build_installer.py`.
*   **Inno Setup Compiler**: `ISCC.exe` from [jrsoftware.org](https://jrsoftware.org/isinfo.php). Ensure it's in your system's PATH or its full path is provided to `build_installer.py`.

## 4. Core Components

### 4.1. `scripts/installer.iss` (Inno Setup Script Template)
This script is processed by `ISCC.exe` to create the installer. It's a template where placeholders are filled in by `build_installer.py`.
*   **Key Preprocessor Directives (defined by `build_installer.py`)**:
    *   `#define AppName "YourApplicationName"`
    *   `#define AppVersion "1.0.0"`
    *   `#define AppPublisher "YourCompany"`
    *   `#define AppURL "YourAppURL"`
    *   `#define BuildDir "path\to\staged\application\files"` (Path to where `package_app.py` places files)
    *   `#define OutputDir "path\to\output\installers"`
    *   `#define AppIcon "path\to\your\app.ico"` (For shortcuts and Add/Remove Programs)
*   **`[Setup]` Section Parameters (derived from defines)**:
    *   `AppId={{<GUID>}-{#AppName}}`: Unique identifier for the application.
    *   `AppName={#AppName}`
    *   `AppVersion={#AppVersion}`
    *   `DefaultDirName={userpf}\{#AppName}`: Default installation path.
    *   `OutputBaseFilename={#AppName}-{#AppVersion}-Installer-UserSetup`: Naming pattern for the installer.
    *   `UninstallDisplayIcon={app}\{#AppIconName}` (where `AppIconName` is the filename of the icon copied to the install dir)

### 4.2. `scripts/setup.ps1` (PowerShell Setup Script)
Executed by the Inno Setup installer on the user's machine. Handles the environment setup and application deployment.
*   **Command-line Parameters (passed by Inno Setup's `[Run]` entry)**:
    *   `-InstallPath <string>`: Full path where the application is being installed.
    *   `-CurrentInstalledVersion <string>`: Version of the currently installed application, if any.
    *   `-NewAppVersion <string>`: Version of the application being installed.
    *   `-AppIdForRegistry <string>`: Application ID for the Uninstall registry key.

### 4.3. `scripts/package_app.py` (Application Packager)
Prepares Python application files for bundling by Inno Setup.
*   **Tasks**:
    *   Copies the application source code from the directory specified by `--app-source`.
    *   Copies `requirements.txt` from the application source directory.
    *   Copies the application icon specified by `--app-icon`.
    *   Copies `setup.ps1` from the `scripts/` directory.
    *   Places all these files into the staging directory specified by `--build-dir`.
*   **Expected Command-line Arguments**:
    *   `--app-source <path>`: Path to the application's source code directory.
    *   `--build-dir <path>`: Path to the output directory for staged files.
    *   `--app-icon <path>`: Path to the application's `.ico` file.

### 4.4. `scripts/build_installer.py` (Installer Builder)
Automates the compilation of the `installer.iss` script. **This script is the main entry point for creating the final installer. It orchestrates the packaging by first calling `package_app.py` with appropriate parameters derived from its own arguments, and then invokes the Inno Setup compiler (`ISCC.exe`) with all necessary parameters and definitions.**
*   **Expected Command-line Arguments**:
    *   `--iss-file <path>`: Path to `scripts/installer.iss`.
    *   `--app-name <string>`: Application's name.
    *   `--app-version <string>`: Application's version (e.g., "1.0.1").
    *   `--app-source <path>`: Path to the application's source code directory (passed to `package_app.py`).
    *   `--build-dir <path>`: Staging directory for `package_app.py` and input for Inno Setup.
    *   `--output-dir <path>`: Where to save the compiled installer.
    *   `--app-icon <path>`: Path to the application's `.ico` file (passed to `package_app.py` and Inno Setup).
    *   `--app-publisher <string>`: (Optional) Application publisher.
    *   `--app-url <string>`: (Optional) Application URL.

## 5. How It Works (Workflow)

1.  **Development**: Develop your Python application. Ensure dependencies are in `requirements.txt` and an `.ico` file is available.
2.  **Build Installer**: Run `scripts/build_installer.py`, providing all required arguments such as your application's name, version, source path, icon path, and desired output directories.
    *   `build_installer.py` first calls `scripts/package_app.py`. This copies your application files, `requirements.txt`, `setup.ps1`, and the icon to the specified build/staging directory.
    *   `build_installer.py` then calls `ISCC.exe` with `scripts/installer.iss`, passing the necessary definitions (AppName, AppVersion, paths, etc.).
    *   Inno Setup bundles files from the build directory into an `AppName-AppVersion.exe` installer in the specified output directory.
3.  **Distribution**: Distribute the generated `.exe` installer.
4.  **User Installation**: The user runs the installer. Inno Setup extracts files and runs `scripts/setup.ps1`, which sets up the Python environment (downloading embedded Python if required), installs dependencies, and creates registry entries/shortcuts.

## 6. `example_application/`

This directory contains a sample Python application (`core.py`, `logic/api.py`, `ui/layout.py`) with a `requirements.txt`. It serves as a template or test case. When building your own application, you provide the path to your application's source directory as an argument to `build_installer.py` (which then passes it to `package_app.py`).

## 7. `UML/` Directory

Contains PlantUML files visualizing system architecture and workflows:
*   **`activity_workflow.plantuml`**: Shows the overall process flow from packaging to installation.
*   **`component_dev.plantuml`**: Illustrates components involved during development and build.
*   **`component_user.plantuml`**: Shows components as experienced by the end-user.
*   **`sequence_setup.plantuml`**: Details the sequence of operations during `setup.ps1` execution.

## 8. How to Use / Build Process (Example)

This example assumes your application is in a folder named `MyPythonApp` (located at the same level as the `scripts` folder), has an icon `MyPythonApp/myapp.ico`. The build staging directory will be `_build` and the final installer will be in `Output`.

1.  **Ensure `MyPythonApp/requirements.txt` is up-to-date.**
2.  **Build the installer by running `build_installer.py`**:
    ```bash
    python scripts/build_installer.py ^
        --iss-file "scripts/installer.iss" ^
        --app-name "MyPythonApp" ^
        --app-version "1.0.0" ^
        --app-source "MyPythonApp" ^
        --build-dir "_build" ^
        --output-dir "Output" ^
        --app-icon "MyPythonApp/myapp.ico" ^
        --app-publisher "My Company" ^
        --app-url "www.example.com"
    ```
    *(Note: `^` is the line continuation character for Windows Command Prompt. Use `\` for PowerShell or bash.)*
3.  **Find your installer**: `Output/MyPythonApp-1.0.0.exe` (or similar, based on `OutputBaseFilename` in `installer.iss`).

## 9. Features

*   **User-Friendly Installation**: End-users do not need Python pre-installed.
*   **Automated Python Provisioning**: Installer downloads and sets up the correct Python version.
*   **Dependency Management**: Installs packages from `requirements.txt`.
*   **User-Specific Installation**: No admin rights needed.
*   **Versioning & Registry**: Correctly versions and registers the application for Add/Remove Programs.
*   **Shortcuts**: Creates Desktop and Start Menu shortcuts.
*   **Customizable Icons**: Uses provided icons for installer and shortcuts.
*   **Automated Build**: Single command (`build_installer.py`) to package and compile.

## 10. Installation Experience

*   Standard Windows installer wizard.
*   No admin rights required.
*   Listed in Add/Remove Programs for clean uninstallation.
*   Desktop/Start Menu shortcuts created.

## 11. Troubleshooting

*   **Installation Logs**: Check `Installation_Log_*.txt` in the application's installation directory (from `setup.ps1`).
*   **Build Logs**: Review the console output from `build_installer.py` which includes output from `ISCC.exe`.
*   **Permissions**: Ensure the target installation directory is writable by the user.
*   **PowerShell Execution Policy**: `setup.ps1` is run with `-ExecutionPolicy Bypass`.
*   **Python Download Issues**: Verify network connectivity and the Python download URL in `setup.ps1`.

