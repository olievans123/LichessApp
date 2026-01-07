#!/usr/bin/env python3
"""Generate app icon with pawn on gradient background"""

from PIL import Image, ImageDraw
import math

def create_rounded_gradient(size, radius_ratio=0.18):
    """Create rounded rectangle with Lichess orange gradient"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    margin = int(size * 0.02)
    radius = int(size * radius_ratio)

    for y in range(size):
        ratio = y / size
        r = int(235 - ratio * 45)
        g = int(145 - ratio * 35)
        b = int(65 - ratio * 25)

        for x in range(size):
            in_rect = True
            if x < margin + radius and y < margin + radius:
                dist = math.sqrt((x - margin - radius)**2 + (y - margin - radius)**2)
                in_rect = dist <= radius
            elif x > size - margin - radius - 1 and y < margin + radius:
                dist = math.sqrt((x - (size - margin - radius - 1))**2 + (y - margin - radius)**2)
                in_rect = dist <= radius
            elif x < margin + radius and y > size - margin - radius - 1:
                dist = math.sqrt((x - margin - radius)**2 + (y - (size - margin - radius - 1))**2)
                in_rect = dist <= radius
            elif x > size - margin - radius - 1 and y > size - margin - radius - 1:
                dist = math.sqrt((x - (size - margin - radius - 1))**2 + (y - (size - margin - radius - 1))**2)
                in_rect = dist <= radius
            elif x < margin or x >= size - margin or y < margin or y >= size - margin:
                in_rect = False

            if in_rect:
                img.putpixel((x, y), (r, g, b, 255))

    return img

def create_icon(size, pawn_img):
    """Create icon at specified size"""
    # Create gradient background
    img = create_rounded_gradient(size)

    # Resize pawn to fit nicely (about 70% of icon size)
    pawn_size = int(size * 0.7)
    pawn_resized = pawn_img.resize((pawn_size, pawn_size), Image.Resampling.LANCZOS)

    # Center the pawn
    offset = (size - pawn_size) // 2

    # Paste pawn onto gradient
    img.paste(pawn_resized, (offset, offset), pawn_resized)

    return img

def main():
    import os

    # Load pawn image
    pawn = Image.open('/tmp/pawn.png').convert('RGBA')

    # macOS icon sizes
    sizes = [16, 32, 64, 128, 256, 512, 1024]

    icon_dir = "LichessApp/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(icon_dir, exist_ok=True)

    for size in sizes:
        icon = create_icon(size, pawn)
        icon.save(f"{icon_dir}/icon_{size}x{size}.png")
        print(f"Created {size}x{size}")

    # Contents.json
    import json
    contents = {
        "images": [
            {"filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
            {"filename": "icon_64x64.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
            {"filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
            {"filename": "icon_1024x1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"},
        ],
        "info": {"author": "xcode", "version": 1}
    }
    with open(f"{icon_dir}/Contents.json", 'w') as f:
        json.dump(contents, f, indent=2)

    print("Done!")

if __name__ == "__main__":
    main()
