## How it works

Displays presentation slides from QSPI flash on a VGA display.
You can navigate between them using a rotary encoder.

## How to test

- Connect VGA Pmod to OUTPUT
- Connect QSPI Pmod to BIDIR
- Connect Rotary Pmod to INPUT (or simulate it with buttons / switches / commander app / micropython)
- Flash the demo slides in `data/slides.bin` to the QSPI Pmod using the
  [Tiny Tapeout flasher](https://tinytapeout.github.io/tinytapeout-flasher/)
- Select the design
- Set the clock to 50 MHz and reset the design
- The first slide should appear
- Turn the rotary encoder clockwise to advance to the next slide
  (there are 5 slides in the demo bitstream)
- Turn the encoder counterclockwise to return to the previous slide
- You can compare the displayed slides to the images in the `data` directory

Using your own slides:

- Prepare up to 32 slides as 640x480 pre-rendered images
- Copy them into `data` as `slide1.png`, `slide2.png`, etc.
- Run `flashgen.py` in the `data` directory
- Continue with the generated `slides.bin` as above

If you find that a few pixels on the left or right side of the screen are cut off,
there is a debug mechanism to tweak the QSPI to VGA delay. Press down on the rotary
encoder and turn it clockwise or counterclockwise to adjust in half-pixel increments.

## External hardware

- [Tiny VGA Pmod](https://github.com/mole99/tiny-vga)
- [QSPI Pmod](https://github.com/mole99/qspi-pmod)
- [Rotary Pmod](https://github.com/TinyTapeout/pcb-files/tree/main/PMOD/pmod-rotaryencoder-v1p1) (optional)
