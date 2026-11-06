#!/usr/bin/env python3
"""
Generates a Tahoe Glass styled background image for the Voice.AI DMG installer window.
Dimensions: 600x400 (and 1200x800 @2x)
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

def create_dmg_background(output_path, scale=2):
    width = 600 * scale
    height = 400 * scale
    
    # Create RGBA canvas with dark obsidian glass theme
    img = Image.new("RGBA", (width, height), (13, 17, 23, 255))
    draw = ImageDraw.Draw(img)
    
    # Subtle radial or vertical gradient
    for y in range(height):
        ratio = y / height
        # Gradient from #0d1117 (13, 17, 23) to #161b22 (22, 27, 34)
        r = int(13 + (22 - 13) * ratio)
        g = int(17 + (27 - 17) * ratio)
        b = int(23 + (34 - 23) * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))
        
    # Draw top glass highlight border
    draw.line([(0, 0), (width, 0)], fill=(255, 255, 255, 30), width=scale)
    
    # Subtle accent glow in center
    center_x = width // 2
    center_y = int(195 * scale)
    
    # Draw Tahoe glass instruction pills for App icon drop target
    # Left container for VoiceOS
    left_x = int(155 * scale)
    right_x = int(445 * scale)
    card_y = int(195 * scale)
    card_r = int(60 * scale)
    
    # Subtle rounded target areas
    target_box_left = [left_x - card_r, card_y - card_r, left_x + card_r, card_y + card_r]
    target_box_right = [right_x - card_r, card_y - card_r, right_x + card_r, card_y + card_r]
    
    draw.rounded_rectangle(target_box_left, radius=int(18 * scale), fill=(255, 255, 255, 8), outline=(255, 255, 255, 20), width=scale)
    draw.rounded_rectangle(target_box_right, radius=int(18 * scale), fill=(255, 255, 255, 8), outline=(255, 255, 255, 20), width=scale)
    
    # Draw arrow between left and right
    arrow_len = int(40 * scale)
    arrow_start = center_x - (arrow_len // 2)
    arrow_end = center_x + (arrow_len // 2)
    arrow_y = card_y
    
    # Arrow line
    draw.line([(arrow_start, arrow_y), (arrow_end, arrow_y)], fill=(120, 150, 255, 180), width=int(3 * scale))
    # Arrow head
    draw.polygon([
        (arrow_end, arrow_y),
        (arrow_end - int(10 * scale), arrow_y - int(7 * scale)),
        (arrow_end - int(10 * scale), arrow_y + int(7 * scale))
    ], fill=(120, 150, 255, 220))
    
    # Subtitle text: "Drag Voice.AI to Applications"
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", int(14 * scale))
    except Exception:
        font = ImageFont.load_default()
        
    text = "Drag Voice.AI to Applications"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    draw.text((center_x - text_w // 2, int(290 * scale)), text, fill=(160, 175, 200, 220), font=font)
    
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    img.save(output_path, "PNG")
    print(f"Generated background: {output_path} ({width}x{height})")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "build/dmg_background.png"
    create_dmg_background(out, scale=2)

