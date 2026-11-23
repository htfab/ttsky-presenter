#!/usr/bin/env python3

import os
from PIL import Image

MAX_SLIDES = 32
W, H = 640, 480
WE, HE = 1024, 512

num_slides = 0
slides = {}
for i in range(1, MAX_SLIDES+1):
    path = f'slide{i}.png'
    if not os.path.exists(path):
        break
    num_slides = i
    slides[i] = path

line_header = bytes((0xa5, 0xc3))  # for QSPI delay autodetection

flash = open('slides.bin', 'wb')

for i in range(1, num_slides+1):
    img = Image.open(slides[i]).convert('RGB')
    assert img.width == W
    assert img.height == H
    data = img.load()
    for y in range(HE):
        flash.write(line_header)
        for x in range(WE - len(line_header)):
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
            elif x == 0 and y == H:
                # encode the slide count so that we can stop at the end
                byte = (
                    0                         << 7 |
                    ((num_slides - 1) & 0x38) << 4 |
                    1                         << 3 |
                    ((num_slides - 1) & 0x07) << 0
                )
            else:
                byte = 0
            flash.write(bytes((byte,)))

flash.close()

