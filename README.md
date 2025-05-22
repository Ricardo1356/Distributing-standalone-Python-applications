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
│   ├── build_config.json       # Configuration file for the build process
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
*   **Inno Setup Compiler**: `ISCC.exe` from [jrsoftware.org](https://jrsoftware.org/isinfo.php). Ensure it's in your system's PATH or its full path is provided in the configuration.

## 4. Core Components

### 4.1. `scripts/installer.iss` (Inno Setup Script Template)
This script is processed by `ISCC.exe` to create the installer. It's a template where placeholders are filled in by `build_installer.py`.
*   **Key Preprocessor Directives (defined by `build_installer.py`)**:
    *   `#define AppName "YourApplicationName"`
    *   `#define AppVersion "1.0.0"`
    *   `#define BuildDir "path\\to\\staged\\application\\files"` (Path to where `package_app.py` places files for Inno Setup to bundle)
*   **`[Setup]` Section Parameters (derived from defines or set directly)**:
    *   `AppId={{<GUID>}-{#AppName}}`: Unique identifier for the application. **Note:** The `<GUID>` part in `{{<GUID>}-{#AppName}}` (e.g., `ef824ac7-86d2-49a4-8bd5-b8b538fc11fe` as seen in the `installer.iss` template) is an example; developers should generate a new, unique GUID for their own application to avoid conflicts.
    *   `AppName={#AppName}`
    *   `AppVersion={#AppVersion}`
    *   `DefaultDirName={userpf}\\{#AppName}`: Default installation path.
    *   `OutputBaseFilename={#AppName}-{#AppVersion}`: Naming pattern for the installer. The final installer will be, e.g., `YourApplicationName-1.0.0.exe`.
    *   `UninstallDisplayIcon={app}\\{#AppName}.ico`: Icon shown in Add/Remove Programs. This requires an icon file named `YourApplicationName.ico` to be present in the root of the application installation directory (`{app}`).
*   **Icon Handling Note**: For the `UninstallDisplayIcon` and icons defined in the `[Icons]` section (e.g., `IconFilename: "{app}\\{#AppName}.ico"`) to work correctly, an icon file (e.g., `YourApplicationName.ico`) must be placed by the packaging process into the root of the `BuildDir` so it gets copied to `{app}` during installation. The provided `package_app.py` does not currently have a dedicated argument to handle this; you would need to ensure your application source (`app_folder` provided to `package_app.py`) contains this icon at its root, or modify `package_app.py` to copy a specified icon file to the root of its `out-dir`.

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
    *   Copies the application source code from the directory specified by the positional `app_folder` argument.
    *   Copies `requirements.txt` from the application source directory.
    *   Copies `setup.ps1` and `setup_gui.ps1` (if present) from the `scripts/` directory.
    *   Creates `metadata.txt` (with AppName, AppFolder, EntryFile, Version, PythonVersion).
    *   Creates `boot.py` (the Python launcher executed by shortcuts).
    *   Creates `custom_pth.txt` (for the Python environment).
    *   Creates `setup.bat` (a helper for manually running `setup.ps1`).
    *   Places all these into the staging directory (specified by `--out-dir`), organized into an `_internal` subdirectory and an application subdirectory (named after `--app-name`).
*   **Command-line Arguments**:
    *   `app_folder` (positional): Path to the application's source code directory (e.g., containing your main script and `requirements.txt`).
    *   `--app-name <string>`: Application's name. Defaults to the `app_folder` name.
    *   `--entry-file <string>`: The main Python script file within your application source (e.g., `core.py`). Default: `core.py`.
    *   `--version <string>`: Application's version (e.g., "1.0.0"). Default: `1.0.0`.
    *   `--out-dir <path>`: Path to the output directory where staged files will be placed. Default: `_temp/<AppName>_pkg`.

### 4.4. `scripts/build_installer.py` (Installer Builder)
Automates the compilation of the `installer.iss` script. **This script is the main entry point for creating the final installer. It uses the configuration from `build_config.json`, orchestrates the packaging by calling `package_app.py` with appropriate parameters, and then invokes the Inno Setup compiler (`ISCC.exe`) with all necessary parameters and definitions.**

### 4.5. `scripts/build_config.json` (Build Configuration)
Contains all the configuration settings for the build process in JSON format.
*   **Configuration Parameters**:
    *   `appName`: Name of your application.
    *   `appVersion`: Application's version string.
    *   `appFolder`: Path to your Python project's root directory.
    *   `issPath`: Path to your Inno Setup `.iss` script template.
    *   `outputDir`: Where to write the final installer `.exe`.
    *   `entryFile`: Entrypoint Python file within your project.
    *   `isccPath`: (Optional) Explicit path to `ISCC.exe`.

## 5. How It Works (Workflow)

1.  **Development**: Develop your Python application. Ensure dependencies are in `requirements.txt`. If you want an application icon, prepare an `.ico` file.
2.  **Configure Build**: Update the `scripts/build_config.json` file with your application details (name, version, paths, etc.).
3.  **Build Installer**: Run `scripts/build_installer.py` without any arguments. It will:
    *   Read configuration from `build_config.json`.
    *   Call `scripts/package_app.py` with the appropriate parameters from the configuration. This copies your application files, `requirements.txt`, `setup.ps1`, etc., into a temporary build/staging directory.
    *   Call `ISCC.exe` with the specified `scripts/installer.iss`. It passes the necessary definitions to Inno Setup: `BuildDir` (the temporary build/staging directory path), `AppName`, and `AppVersion`.
    *   Inno Setup bundles files from the `BuildDir` into an `AppName-AppVersion.exe` installer (e.g., `YourAppName-1.0.0.exe`) in the specified output directory.
4.  **Distribution**: Distribute the generated `.exe` installer.
5.  **User Installation**: The user runs the installer. Inno Setup extracts files and runs `scripts/setup.ps1`, which sets up the Python environment (downloading embeddable Python if required), installs dependencies, and creates registry entries/shortcuts.

## 6. `example_application/`

This directory contains a sample Python application (`core.py`, `logic/api.py`, `ui/layout.py`) with a `requirements.txt`. It serves as a template or test case. When building your own application, you specify the path to your application's source directory in the `build_config.json` file.

## 7. `UML/` Directory

Contains PlantUML files visualizing system architecture and workflows:
*   **`activity_workflow.plantuml`**: Shows the overall process flow from packaging to installation.
*   **`component_dev.plantuml`**: Illustrates components involved during development and build.
*   **`component_user.plantuml`**: Shows components as experienced by the end-user.
*   **`sequence_setup.plantuml`**: Details the sequence of operations during `setup.ps1` execution.

## 8. How to Use / Build Process (Example)

This example assumes your application is in a folder named `MyPythonApp` (located at the same level as the `scripts` folder).

1.  **Ensure `MyPythonApp/requirements.txt` is up-to-date.**
2.  **(Optional but Recommended for Icons):** Place an icon file named `MyPythonApp.ico` into the `MyPythonApp/` source directory if you want it to be used as the application icon by default (see Icon Handling Note in Section 4.1).
3.  **Update the `scripts/build_config.json` file**:
    ```json
    {
      "appName": "MyPythonApp",
      "appVersion": "1.0.0",
      "appFolder": "./MyPythonApp",
      "issPath": "installer.iss",
      "outputDir": "./dist",
      "entryFile": "core.py",
      "isccPath": null
    }
    ```
4.  **Build the installer by running `build_installer.py`**:
    ```bash
    python scripts/build_installer.py
    ```
5.  **Find your installer**: `dist/MyPythonApp-1.0.0.exe` (based on the configuration in `build_config.json`).

## 9. Features

*   **User-Friendly Installation**: End-users do not need Python pre-installed.
*   **Automated Python Provisioning**: Installer downloads and sets up the correct Python version.
*   **Dependency Management**: Installs packages from `requirements.txt`.
*   **User-Specific Installation**: No admin rights needed.
*   **Versioning & Registry**: Correctly versions and registers the application for Add/Remove Programs.
*   **Shortcuts**: Creates Desktop and Start Menu shortcuts.
*   **Customizable Icons**: Uses provided icons for installer and shortcuts.
*   **Automated Build**: Single command (`build_installer.py`) to package and compile.
*   **Centralized Configuration**: All build settings in one `build_config.json` file.

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

