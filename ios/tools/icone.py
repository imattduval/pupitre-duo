#!/usr/bin/env python3
"""Dessine l'icône de Pupitre : un accord au-dessus de lignes de paroles. Usage : icone.py sortie.png"""
import sys
from PIL import Image, ImageDraw, ImageFont

image = Image.new("RGB", (1024, 1024), (17, 18, 20))
draw = ImageDraw.Draw(image)
font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 310, index=1)
draw.text((140, 110), "Am7", font=font, fill=(255, 200, 92))
for y, width, shade in [(540, 700, (243, 241, 236)), (680, 520, (140, 139, 136)), (820, 610, (82, 82, 82))]:
    draw.rounded_rectangle((162, y, 162 + width, y + 64), radius=32, fill=shade)
image.save(sys.argv[1])
