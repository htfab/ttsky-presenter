import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

import os
import glob
import itertools
from PIL import Image, ImageChops

from qspi_pmod import qspi_pmod


async def send_input(dut, sequence, delay):
    for entry in sequence:
        dut.ui_in.value = entry
        await ClockCycles(dut.clk, delay)


@cocotb.test()
async def test_project(dut):

    # Enable verbose mode to debug a failing test
    VERBOSE = False

    # Flash data for QSPI Pmod
    QSPI_FLASH_BIN = "../data/slides.bin"

    # Set clock period to 20 ns (50 MHz)
    CLOCK_PERIOD = 20

    # Set VGA timing parameters matching hvsync_generator.v
    H_DISPLAY = 640
    H_FRONT   =  16
    H_SYNC    =  96
    H_BACK    =  48
    V_DISPLAY = 480
    V_FRONT   =  10
    V_SYNC    =   2
    V_BACK    =  33

    # Number of frames to capture
    CAPTURE_FRAMES = 10

    # Number of slides available
    NUM_SLIDES = 5

    # Derived constants
    H_SYNC_START = H_DISPLAY + H_FRONT
    H_SYNC_END = H_SYNC_START + H_SYNC
    H_TOTAL = H_SYNC_END + H_BACK
    V_SYNC_START = V_DISPLAY + V_FRONT
    V_SYNC_END = V_SYNC_START + V_SYNC
    V_TOTAL = V_SYNC_END + V_BACK

    # Palette mapping uo_out values to RGB color
    palette = [0] * 256
    for r1, r0, g1, g0, b1, b0 in itertools.product(range(2), repeat=6):
        red = 170*r1 + 85*r0
        green = 170*g1 + 85*g0
        blue = 170*b1 + 85*b0
        palette[1<<7|b0<<6|g0<<5|r0<<4|1<<3|b1<<2|g1<<1|r1<<0] = bytes((red, green, blue))

    # Set up the clock
    # => this was moved to the Verilog testbench tb.v
    #    for massive memory usage & speed improvements
    #clock = Clock(dut.clk, CLOCK_PERIOD, unit="ns")
    #cocotb.start_soon(clock.start())

    # Attach the simulated QSPI Pmod
    cocotb.start_soon(qspi_pmod(dut, QSPI_FLASH_BIN, VERBOSE))

    # Reset the design
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)

    # Define some functions for capturing lines & frames

    async def check_line(expected_vsync):
        for i in range(H_TOTAL):
            hsync = dut.uo_out.value[7]
            vsync = dut.uo_out.value[3]
            assert hsync == (0 if H_SYNC_START <= i < H_SYNC_END else 1), "Unexpected hsync pattern"
            assert vsync == expected_vsync, "Unexpected vsync pattern"
            await ClockCycles(dut.clk, 2)

    async def capture_line(framebuffer, offset):
        for i in range(H_TOTAL):
            hsync = dut.uo_out.value[7]
            vsync = dut.uo_out.value[3]
            assert hsync == (0 if H_SYNC_START <= i < H_SYNC_END else 1), "Unexpected hsync pattern"
            assert vsync == 1, "Unexpected vsync pattern"
            if i < H_DISPLAY:
                framebuffer[offset+3*i:offset+3*i+3] = palette[dut.uo_out.value.to_unsigned()]
            await ClockCycles(dut.clk, 2)

    async def skip_frame(frame_num):
        dut._log.info(f"Skipping frame {frame_num}")
        await ClockCycles(dut.clk, H_TOTAL*V_TOTAL*2)

    async def capture_frame(frame_num, check_sync=True, action=None):
        dut._log.info(f"Rendering frame {frame_num}")
        framebuffer = bytearray(V_DISPLAY*H_DISPLAY*3)
        for j in range(V_DISPLAY):
            if VERBOSE:
                dut._log.info(f"Frame {frame_num}, line {j} (display)")
            line = await capture_line(framebuffer, 3*j*H_DISPLAY)
        if action is not None:
            cocotb.start_soon(action)
        if check_sync:
            for j in range(j, j+V_FRONT):
                if VERBOSE:
                    dut._log.info(f"Frame {frame_num}, line {j} (front porch)")
                await check_line(1)
            for j in range(j, j+V_SYNC):
                if VERBOSE:
                    dut._log.info(f"Frame {frame_num}, line {j} (sync pulse)")
                await check_line(0)
            for j in range(j, j+V_BACK):
                if VERBOSE:
                    dut._log.info(f"Frame {frame_num}, line {j} (back porch)")
                await check_line(1)
        else:
            if VERBOSE:
                dut._log.info(f"Frame {frame_num}, skipping non-display lines")
            await ClockCycles(dut.clk, H_TOTAL*(V_TOTAL-V_DISPLAY)*2)
        frame = Image.frombytes('RGB', (H_DISPLAY, V_DISPLAY), bytes(framebuffer))
        return frame

    # Start capturing

    os.makedirs("output", exist_ok=True)

    await skip_frame(0)
    cur_slide = 1
    slide_dir = 1
    for i in range(1, CAPTURE_FRAMES+1):
        if slide_dir == 1 and cur_slide >= NUM_SLIDES:
            slide_dir = -1
        elif slide_dir == -1 and cur_slide <= 1:
            slide_dir = 1
        if slide_dir == 1:
            action = send_input(dut, (2, 3, 1, 0), 20)
            cur_slide += 1
        elif slide_dir == -1:
            action = send_input(dut, (1, 3, 2, 0), 20)
            cur_slide -= 1
        frame = await capture_frame(i, action=action)
        frame.save(f"output/frame{i:03}.png")


@cocotb.test()
async def compare_reference(dut):

    for img in glob.glob("output/frame*.png"):
        basename = img.removeprefix("output/")
        dut._log.info(f"Comparing {basename} to reference image")
        frame = Image.open(img)
        ref = Image.open(f"reference/{basename}")
        diff = ImageChops.difference(frame, ref)
        if diff.getbbox() is not None:
            diff.save(f"output/diff_{basename}")
            assert False, f"Rendered {basename} differs from reference image"
