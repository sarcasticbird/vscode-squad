#!/usr/bin/env python3
"""Resize a 1024x1024 source icon into all macOS AppIcon sizes using sips."""

import json
import os
import subprocess
import sys

SIZES = [
    (16,   "icon_16x16.png",       "1x", "16x16"),
    (32,   "icon_16x16@2x.png",    "2x", "16x16"),
    (32,   "icon_32x32.png",       "1x", "32x32"),
    (64,   "icon_32x32@2x.png",    "2x", "32x32"),
    (128,  "icon_128x128.png",     "1x", "128x128"),
    (256,  "icon_128x128@2x.png",  "2x", "128x128"),
    (256,  "icon_256x256.png",     "1x", "256x256"),
    (512,  "icon_256x256@2x.png",  "2x", "256x256"),
    (512,  "icon_512x512.png",     "1x", "512x512"),
    (1024, "icon_512x512@2x.png",  "2x", "512x512"),
]

CONTENTS = {
    "images": [],
    "info": {"author": "xcode", "version": 1},
}


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    source = os.path.join(script_dir, "icon_source.png")

    if not os.path.exists(source):
        print(f"Error: {source} not found. Run generate_logo.py first.", file=sys.stderr)
        sys.exit(1)

    output_dir = os.path.join(
        script_dir, "..", "CodeSquad", "Assets.xcassets", "AppIcon.appiconset"
    )
    os.makedirs(output_dir, exist_ok=True)

    images = []
    for size_px, filename, scale, size_label in SIZES:
        output_path = os.path.join(output_dir, filename)

        subprocess.run([
            "sips", "-z", str(size_px), str(size_px),
            source, "--out", output_path,
        ], capture_output=True, check=True)

        images.append({
            "filename": filename,
            "idiom": "mac",
            "scale": scale,
            "size": size_label,
        })
        print(f"  {filename} ({size_px}x{size_px})")

    CONTENTS["images"] = images
    contents_path = os.path.join(output_dir, "Contents.json")
    with open(contents_path, "w") as f:
        json.dump(CONTENTS, f, indent=2)
        f.write("\n")

    print(f"\nGenerated {len(images)} icons in {output_dir}")


if __name__ == "__main__":
    main()
