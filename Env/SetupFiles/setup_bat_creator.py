#!/usr/bin/env python3
import os
import sys

def create_setup_bat(target_folder):
    bat_path = os.path.join(target_folder, "setup.bat")
    bat_content = (
        '@echo off\r\n'
        'powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0\\SetupFiles\\setup.ps1"\r\n'
        'pause\r\n'
    )
    with open(bat_path, "w", encoding="ascii") as f:
        f.write(bat_content)
    print(f"Created setup.bat at {bat_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: setup_bat_creator.py <target_folder>")
        sys.exit(1)
    target_folder = sys.argv[1]
    create_setup_bat(target_folder)
