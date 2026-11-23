`default_nettype none

module qspi (
    input  wire clk,
    input  wire rst_n,
    input  wire [23:0] addr,    // memory address to read from
    input  wire start_read,
    input  wire stop_read,
    input  wire [7:0] uio_in,   // connected to QSPI PMOD (input)
    output wire [7:0] uio_out,  // connected to QSPI PMOD (output)
    output wire [7:0] uio_oe,   // connected to QSPI PMOD (output enable)
    output wire [3:0] data,
    output wire start_data
);

// State machine for sequencing QSPI commands

reg [7:0] state;
reg [7:0] next_state;
reg [10:0] microcode;
reg [10:0] next_microcode;
reg slow_clk;
reg next_slow_clk;
wire advance;

// Logic for state transitions

always_comb begin
    next_state = state;
    next_slow_clk = 0;
    if (!rst_n) begin
        next_state = 8'h00;  // init
    end else if (start_read) begin
        next_state = 8'h10;  // start read
    end else if (stop_read) begin
        next_state = 8'h20;  // idle
    end else if (advance) begin
        // auto-advance to the next state if the "advance" bit
        // is set for the current state in the microcode table
        if (slow_clk) begin
            next_state = state + 1;
        end else begin
            next_slow_clk = 1;
        end
    end
end

// Set uio pins, clocking & advance bit based on state

always_comb begin             // slow           qspi   qspi
    case (next_state)         //  clk  adv cs    oe     out
        // init
        8'h00: next_microcode = 11'b1___1___1___0000___0000;
        8'h01: next_microcode = 11'b1___1___0___1111___1111;  // QPI FFh (exit QPI mode)
        8'h02: next_microcode = 11'b1___1___0___1111___1111;
        8'h03: next_microcode = 11'b1___1___1___0000___0000;
        8'h04: next_microcode = 11'b1___1___0___0001___0000;  // SPI 38h (enter QPI mode)
        8'h05: next_microcode = 11'b1___1___0___0001___0000;
        8'h06: next_microcode = 11'b1___1___0___0001___0001;
        8'h07: next_microcode = 11'b1___1___0___0001___0001;
        8'h08: next_microcode = 11'b1___1___0___0001___0001;
        8'h09: next_microcode = 11'b1___1___0___0001___0000;
        8'h0a: next_microcode = 11'b1___1___0___0001___0000;
        8'h0b: next_microcode = 11'b1___1___0___0001___0000;
        8'h0c: next_microcode = 11'b1___0___1___0000___0000;
        // start read
        8'h10: next_microcode = 11'b1___1___1___0000___0000;
        8'h11: next_microcode = 11'b1___1___0___1111___1110;  // QPI EBh (fast read)
        8'h12: next_microcode = 11'b1___1___0___1111___1011;
        8'h13: next_microcode = {7'b1___1___0___1111, addr[23:20]};
        8'h14: next_microcode = {7'b1___1___0___1111, addr[19:16]};
        8'h15: next_microcode = {7'b1___1___0___1111, addr[15:12]};
        8'h16: next_microcode = {7'b1___1___0___1111, addr[11: 8]};
        8'h17: next_microcode = {7'b1___1___0___1111, addr[ 7: 4]};
        8'h18: next_microcode = {7'b1___1___0___1111, addr[ 3: 0]};
        8'h19: next_microcode = 11'b1___1___0___1111___1111;
        8'h1a: next_microcode = 11'b0___0___0___0000___0000;
        // idle
        8'h20: next_microcode = 11'b1___0___1___0000___0000;
        // end of table
      default: next_microcode = 11'b1___0___1___0000___0000;
    endcase
end

// Registering the microcode independently from the state helps prevent
// glitches where the state bits don't arrive exactly at the same time

always @(posedge clk) begin
    // !rst_n is already handled by the blocks above
    state <= next_state;
    slow_clk <= next_slow_clk;
    microcode <= next_microcode;
end

// We use the slow clock (divided by 2) when sending commands to make sure
// the outputs don't change at the positive clock edge.

// We use the fast clock (main project clock) while reading data from
// the flash chip to achieve maximum bandwidth.

wire slow_mode = microcode[10];
wire qspi_clk = slow_mode ? slow_clk : clk;

assign advance = microcode[9];  // auto-advance to next state
wire cs_flash = microcode[8];   // chip select: use flash chip on QSPI PMOD
wire [3:0] qspi_oe = microcode[7:4];
wire [3:0] qspi_out = microcode[3:0];

wire next_advance = next_microcode[9];

// Handling the bidirectional I/O pins

assign uio_out = {2'b11, qspi_out[3:2], qspi_clk, qspi_out[1:0], cs_flash};
assign uio_oe = {2'b11, qspi_oe[3:2], 1'b1, qspi_oe[1:0], 1'b1};
assign data = {uio_in[5:4], uio_in[2:1]};
assign start_data = (state[7:4] == 1 && advance && !next_advance);

// Suppress unused signals warning
wire _unused_ok = &{uio_in[7:6], uio_in[3], uio_in[0]};

endmodule
