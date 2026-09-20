
/**
 * Streaming MAC reduction: for each group of M=4 elements, emit the dot
 * product y = sum(a[i]*b[i]). Two input streams; BOTH read unconditionally
 * every cycle — the reduction is gated by a counter, not by conditional stream
 * access. (A per-group side input read conditionally is fine when it is a
 * `stream`, whose handshake paces it — but reading every cycle is the simplest
 * shape and works for `push` too; see cg_docs handshakes.) A running
 * accumulator holds partial state, emitted and cleared on the last element.
 * 
 * Operands are UNSIGNED here for portability. A SIGNED inline `a*b` of stream
 * inputs also works on the current toolchain (the Verilog backend distributes
 * the sign-extension over the handshake mux). On releases <= 2.9.0 keep them
 * unsigned or route the product through std.math.Multiply (see MulStream).
 */
module StreamDot(input clock, input reset_n, input [31 : 0] a, input a_valid, input [31 : 0] b, input b_valid, output [63 : 0] y, output y_valid);


  /**
   * Wires
   */
  // Module : src
  wire [31 : 0] src_fa;
  wire src_fa_ready;
  wire src_fa_valid;
  wire [31 : 0] src_fb;
  wire src_fb_ready;
  wire src_fb_valid;
  // Module : dut
  wire [63 : 0] dut_oy;
  wire dut_oy_ready;
  wire dut_oy_valid;
  
  /**
   * Instances
   */
  StreamDot_src src (
    .clock(clock),
    .reset_n(reset_n),
    .StreamDot_a(a),
    .StreamDot_a_valid(a_valid),
    .StreamDot_b(b),
    .StreamDot_b_valid(b_valid),
    .fa(src_fa),
    .fa_ready(src_fa_ready),
    .fa_valid(src_fa_valid),
    .fb(src_fb),
    .fb_ready(src_fb_ready),
    .fb_valid(src_fb_valid)
  );
  
  StreamDot_dut dut (
    .clock(clock),
    .reset_n(reset_n),
    .ia(src_fa),
    .ia_ready(src_fa_ready),
    .ia_valid(src_fa_valid),
    .ib(src_fb),
    .ib_ready(src_fb_ready),
    .ib_valid(src_fb_valid),
    .oy(dut_oy),
    .oy_ready(dut_oy_ready),
    .oy_valid(dut_oy_valid)
  );
  
  StreamDot_sink sink (
    .clock(clock),
    .reset_n(reset_n),
    .iy(dut_oy),
    .iy_ready(dut_oy_ready),
    .iy_valid(dut_oy_valid),
    .StreamDot_y(y),
    .StreamDot_y_valid(y_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //StreamDot
