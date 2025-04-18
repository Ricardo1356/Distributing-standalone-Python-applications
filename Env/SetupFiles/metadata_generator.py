#!/usr/bin/env python3
import os
import sys

def create_metadata(target_folder, app_name, app_folder, entry_file, app_version):
    metadata_path = os.path.join(target_folder, "metadata.txt")
    with open(metadata_path, "w", encoding="utf-8") as f:
        f.write(f"AppName={app_name}\n")
        f.write(f"AppFolder={os.path.basename(os.path.abspath(app_folder))}\n")
        f.write(f"EntryFile={entry_file}\n")
        f.write(f"Version={app_version}\n")
    print(f"Created metadata.txt at {metadata_path}")

if __name__ == "__main__":
    if len(sys.argv) < 6:
        print("Usage: metadata_generator.py <target_folder> <app_name> <app_folder> <entry_file> <app_version>")
        sys.exit(1)
    target_folder = sys.argv[1]
    app_name = sys.argv[2]
    app_folder = sys.argv[3]
    entry_file = sys.argv[4]
    app_version = sys.argv[5]
    create_metadata(target_folder, app_name, app_folder, entry_file, app_version)
