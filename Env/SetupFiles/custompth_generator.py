#!/usr/bin/env python3
import sys

def generate_custom_pth(python_version):
    parts = python_version.split(".")
    if len(parts) >= 2:
        base = "python" + parts[0] + parts[1]
    else:
        base = "python" + python_version.replace(".", "")
    content = f"{base}.zip\nLib\n.\nimport site\n"
    return content

def write_custom_pth(target_file, python_version):
    content = generate_custom_pth(python_version)
    with open(target_file, "w", encoding="ascii") as f:
        f.write(content)
    print(f"Created custom_pth.txt at {target_file}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: custompth_generator.py <target_file> <python_version>")
        sys.exit(1)
    target_file = sys.argv[1]
    python_version = sys.argv[2]
    write_custom_pth(target_file, python_version)
