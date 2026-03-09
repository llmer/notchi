#!/usr/bin/env python3
"""
Sprite generator for Notchi — composites new sprite sheets from existing ones.

Usage:
    python3 tools/generate_sprites.py battle

Requires: pip install Pillow
"""

import sys
import json
import math
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Error: Pillow is required. Install with: pip install Pillow")
    sys.exit(1)

ASSET_DIR = Path(__file__).resolve().parent.parent / "notchi" / "notchi" / "Assets.xcassets"
FRAME_SIZE = 64
FRAME_COUNT = 6
SHEET_WIDTH = FRAME_SIZE * FRAME_COUNT  # 384
SHEET_HEIGHT = FRAME_SIZE  # 64

CONTENTS_JSON = {
    "images": [{"filename": "sprite_sheet.png", "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
    "properties": {"preserves-vector-representation": False},
}


def load_spritesheet(name: str) -> Image.Image:
    """Load an existing sprite sheet from the asset catalog."""
    path = ASSET_DIR / f"{name}.imageset" / "sprite_sheet.png"
    if not path.exists():
        raise FileNotFoundError(f"Sprite sheet not found: {path}")
    return Image.open(path).convert("RGBA")


def extract_frames(sheet: Image.Image) -> list[Image.Image]:
    """Split a 384x64 sprite sheet into 6 individual 64x64 frames."""
    frames = []
    for i in range(FRAME_COUNT):
        frame = sheet.crop((i * FRAME_SIZE, 0, (i + 1) * FRAME_SIZE, FRAME_SIZE))
        frames.append(frame.copy())
    return frames


def compose_spritesheet(frames: list[Image.Image]) -> Image.Image:
    """Stitch 6 frames back into a 384x64 strip."""
    sheet = Image.new("RGBA", (SHEET_WIDTH, SHEET_HEIGHT), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        sheet.paste(frame, (i * FRAME_SIZE, 0))
    return sheet


def write_imageset(name: str, image: Image.Image) -> Path:
    """Save PNG + Contents.json to the asset catalog."""
    imageset_dir = ASSET_DIR / f"{name}.imageset"
    imageset_dir.mkdir(parents=True, exist_ok=True)

    png_path = imageset_dir / "sprite_sheet.png"
    image.save(png_path, "PNG")

    contents_path = imageset_dir / "Contents.json"
    contents_path.write_text(json.dumps(CONTENTS_JSON, indent=2) + "\n")

    return imageset_dir


def draw_sword(frame: Image.Image, x: int, y: int, angle_deg: float) -> Image.Image:
    """
    Draw a pixel-art sword onto a frame at (x, y) with the given angle.

    The sword is drawn on a temporary canvas, rotated, then composited.
    Sword design: brown handle, gray crossguard, silver blade with highlight.
    """
    # Draw sword on an oversized transparent canvas (so rotation doesn't clip)
    canvas_size = 48
    sword_img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(sword_img)

    # Sword center in canvas
    cx, cy = canvas_size // 2, canvas_size // 2

    # Handle (brown) — 3x4 block at the bottom of the sword
    handle_color = (101, 67, 33, 255)
    draw.rectangle([cx - 1, cy + 4, cx + 1, cy + 7], fill=handle_color)

    # Crossguard (dark gray) — 1x6 horizontal bar
    guard_color = (100, 100, 110, 255)
    draw.rectangle([cx - 3, cy + 3, cx + 3, cy + 4], fill=guard_color)

    # Blade (silver/steel) — 3px wide, 12px tall going upward
    blade_color = (180, 190, 200, 255)
    draw.rectangle([cx - 1, cy - 8, cx + 1, cy + 3], fill=blade_color)

    # Blade highlight (lighter stripe down the center)
    highlight_color = (220, 230, 240, 255)
    draw.rectangle([cx, cy - 8, cx, cy + 2], fill=highlight_color)

    # Blade tip (pointed)
    tip_color = (200, 210, 220, 255)
    draw.point((cx, cy - 9), fill=tip_color)

    # Rotate the sword canvas
    rotated = sword_img.rotate(angle_deg, resample=Image.BICUBIC, expand=False, center=(cx, cy))

    # Composite onto frame at (x, y) — position the sword center at (x, y)
    result = frame.copy()
    paste_x = x - cx
    paste_y = y - cy
    result.alpha_composite(rotated, (paste_x, paste_y))

    return result


def find_character_bbox(frame: Image.Image) -> tuple[int, int, int, int]:
    """Find the bounding box of non-transparent pixels in a frame."""
    # Get alpha channel
    alpha = frame.split()[3]
    bbox = alpha.getbbox()
    if bbox is None:
        return (16, 16, 48, 48)  # fallback
    return bbox


def generate_battle(base_name: str, output_name: str) -> None:
    """Generate a battle sprite sheet from a base working sprite sheet."""
    print(f"  Loading base: {base_name}")
    sheet = load_spritesheet(base_name)
    frames = extract_frames(sheet)

    # Sword animation keyframes: (angle, x_offset, y_offset) relative to character right side
    # Angles: positive = clockwise rotation
    # The sword progresses through a charging swing animation
    sword_keyframes = [
        (35, 4, 2),    # Frame 0: Sword angled back (ready stance)
        (15, 3, 0),    # Frame 1: Starting to swing forward
        (-10, 2, -2),  # Frame 2: Sword extended forward (full thrust)
        (-5, 3, -1),   # Frame 3: Slight pullback
        (20, 4, 1),    # Frame 4: Swinging back
        (30, 4, 2),    # Frame 5: Back to ready / glint frame
    ]

    battle_frames = []
    for i, frame in enumerate(frames):
        bbox = find_character_bbox(frame)
        # Place sword on the right side of the character, vertically centered
        char_right = bbox[2]
        char_mid_y = (bbox[1] + bbox[3]) // 2

        angle, x_off, y_off = sword_keyframes[i]
        sword_x = min(char_right + x_off, FRAME_SIZE - 6)  # keep in bounds
        sword_y = char_mid_y + y_off

        battle_frame = draw_sword(frame, sword_x, sword_y, angle)
        battle_frames.append(battle_frame)

    battle_sheet = compose_spritesheet(battle_frames)
    out_dir = write_imageset(output_name, battle_sheet)
    print(f"  Written: {out_dir}")


def cmd_battle() -> None:
    """Generate battle sprite sheets from working sprites."""
    print("Generating battle sprites...")

    variants = [
        ("working_neutral", "battle_neutral"),
        ("working_happy", "battle_happy"),
    ]

    for base, output in variants:
        generate_battle(base, output)

    print("Done! Generated battle_neutral and battle_happy sprite sheets.")


COMMANDS = {
    "battle": cmd_battle,
}


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <command>")
        print(f"Commands: {', '.join(COMMANDS.keys())}")
        sys.exit(1)

    command = sys.argv[1]
    if command not in COMMANDS:
        print(f"Unknown command: {command}")
        print(f"Commands: {', '.join(COMMANDS.keys())}")
        sys.exit(1)

    COMMANDS[command]()


if __name__ == "__main__":
    main()
