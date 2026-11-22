`default_nettype none

module fpga_top (
    input wire clk_25mhz,
    input wire [6:0] btn,
    output wire [7:0] led,
    input wire [7:0] ja,
    output wire [7:0] jb,
    inout wire [7:0] jc,
    output wire [7:0] jd,
    output wire keep_alive
);

wire clk_50mhz;
wire clk_locked;

clock_gen #(
    .CLKI_DIV(1),
    .CLKFB_DIV(2),
    .CLKOP_DIV(12),
    .CLKOP_CPHASE(0)
) cg (
    .clk_in(clk_25mhz),
    .clk_out(clk_50mhz),
    .clk_locked(clk_locked)
);

assign led = {^btn, btn[6:1], !btn[0]};
assign keep_alive = 1'b1;

wire rst_n = btn[0] & clk_locked;
wire clk_proj = clk_50mhz;

wire [7:0] ui_in = ja; //{2'b00, btn[6:1]};
wire [7:0] uio_in;
wire [7:0] uio_out;
wire [7:0] uio_oe;
wire [7:0] uo_out;

// add input delay here if needed
wire [7:0] ui_in_delayed = ui_in;
wire [7:0] uio_in_delayed = uio_in;

tt_um_htfab_presenter proj (
    .ui_in(ui_in_delayed),
    .uo_out(uo_out),
    .uio_in(uio_in_delayed),
    .uio_out(uio_out),
    .uio_oe(uio_oe),
    .ena(1'b1),
    .clk(clk_proj),
    .rst_n(rst_n)
);

assign jd = uo_out;

generate genvar i;
for (i=0; i<8; i=i+1) begin
    assign jc[i] = uio_oe[i] ? uio_out[i] : 1'bz;
    assign uio_in[i] = jc[i];
end
endgenerate

assign jb = jc;

endmodule

