#!/usr/bin/env python3

from PIL import Image

SLIDES = 32
W, H = 640, 480
WE, HE = 1024, 512


flash = open('slides.bin', 'wb')

for slide in range(1, SLIDES+1):
    try:
        img = Image.open(f'slide{slide}.png').convert('RGB')
    except FileNotFoundError:
        break
    assert img.width == W
    assert img.height == H
    data = img.load()
    for y in range(HE):
        for x in range(WE):
            if x < W and y < H:
                R, G, B = data[x, y]
                byte = (
                    0              << 7 |
                    ((B >> 6) & 1) << 6 |
                    ((G >> 6) & 1) << 5 |
                    ((R >> 6) & 1) << 4 |
                    1              << 3 |
                    ((B >> 7) & 1) << 2 |
                    ((G >> 7) & 1) << 1 |
                    ((R >> 7) & 1) << 0
                )
            else:
                byte = 0
            flash.write(bytes((byte,)))

flash.close()

