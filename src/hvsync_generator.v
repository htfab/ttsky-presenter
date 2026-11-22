`ifndef HVSYNC_GENERATOR_H
`define HVSYNC_GENERATOR_H

/* This is a modified version of the standard Tiny Tapeout VGA sync generator.
 * Changes:
 *  - use negative reset as is standard on TT
 *  - add a clk_gate input for running the project at a multiple of the VGA clock
 *  - style changes (Verilog-2001 ANSI ports, explicit begin/end for conditionals)
 */

module hvsync_generator(
    input wire clk,
    input wire clk_gate,
    input wire rst_n,
    output reg hsync,
    output reg vsync,
    output wire display_on,
    output reg [9:0] hpos,
    output reg [9:0] vpos
);

// horizontal constants
parameter H_DISPLAY       = 640; // horizontal display width
parameter H_BACK          =  48; // horizontal left border (back porch)
parameter H_FRONT         =  16; // horizontal right border (front porch)
parameter H_SYNC          =  96; // horizontal sync width
// vertical constants
parameter V_DISPLAY       = 480; // vertical display height
parameter V_TOP           =  33; // vertical top border
parameter V_BOTTOM        =  10; // vertical bottom border
parameter V_SYNC          =   2; // vertical sync # lines
// derived constants
parameter H_SYNC_START    = H_DISPLAY + H_FRONT;
parameter H_SYNC_END      = H_DISPLAY + H_FRONT + H_SYNC - 1;
parameter H_MAX           = H_DISPLAY + H_BACK + H_FRONT + H_SYNC - 1;
parameter V_SYNC_START    = V_DISPLAY + V_BOTTOM;
parameter V_SYNC_END      = V_DISPLAY + V_BOTTOM + V_SYNC - 1;
parameter V_MAX           = V_DISPLAY + V_TOP + V_BOTTOM + V_SYNC - 1;

wire hmaxxed = hpos == H_MAX;	// set when hpos is maximum
wire vmaxxed = vpos == V_MAX;	// set when vpos is maximum
  
// horizontal position counter
always @(posedge clk)
begin
    if (!rst_n) begin
        hsync <= 1;
        hpos <= 0;
    end else if (clk_gate) begin
        hsync <= ~(hpos >= H_SYNC_START && hpos <= H_SYNC_END);
        if (hmaxxed) begin
            hpos <= 0;
        end else begin
            hpos <= hpos + 1;
        end
    end
end

// vertical position counter
always @(posedge clk)
begin
    if (!rst_n) begin
        vsync <= 1;
        vpos <= 0;
    end else if (clk_gate) begin
        vsync <= ~(vpos >= V_SYNC_START && vpos <= V_SYNC_END);
        if (hmaxxed) begin
            if (vmaxxed) begin
                vpos <= 0;
            end else begin
                vpos <= vpos + 1;
            end
        end
    end
end

// display_on is set when beam is in "safe" visible frame
assign display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);

endmodule

`endif
