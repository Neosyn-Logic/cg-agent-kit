
/**
 * Streaming signed multiply on the std.math.Multiply built-in — a registered
 * (1-cycle) full-width product, p = a * b. p is int<64> because a 32x32 product
 * overflows 32 bits (the last vector, 46341^2 = 2147488281, is > INT32_MAX).
 * 
 * PATTERN: the feeder/sink tasks adapt the network's external `push` ports to the
 * built-in's `stream` (valid+ready) handshake. Because those internal links are
 * `stream`, the multiplier's back-pressure flows all the way to the source and
 * paces the stream automatically. A single task that wrote both operands and read
 * the product would DROP a vector (the built-in is registered with no input FIFO).
 */
module MulStream(input clock, input reset_n, input signed [31 : 0] a, input a_valid, input signed [31 : 0] b, input b_valid, output signed [63 : 0] p, output p_valid);


  /**
   * Wires
   */
  // Module : feeder
  wire signed [31 : 0] feeder_ma;
  wire feeder_ma_ready;
  wire feeder_ma_valid;
  wire signed [31 : 0] feeder_mb;
  wire feeder_mb_ready;
  wire feeder_mb_valid;
  // Module : mul
  wire signed [63 : 0] mul_p;
  wire mul_p_ready;
  wire mul_p_valid;
  
  /**
   * Instances
   */
  MulStream_feeder feeder (
    .clock(clock),
    .reset_n(reset_n),
    .MulStream_a(a),
    .MulStream_a_valid(a_valid),
    .MulStream_b(b),
    .MulStream_b_valid(b_valid),
    .ma(feeder_ma),
    .ma_ready(feeder_ma_ready),
    .ma_valid(feeder_ma_valid),
    .mb(feeder_mb),
    .mb_ready(feeder_mb_ready),
    .mb_valid(feeder_mb_valid)
  );
  
  Multiply mul (
    .clock(clock),
    .reset_n(reset_n),
    .a(feeder_ma),
    .a_ready(feeder_ma_ready),
    .a_valid(feeder_ma_valid),
    .b(feeder_mb),
    .b_ready(feeder_mb_ready),
    .b_valid(feeder_mb_valid),
    .p(mul_p),
    .p_ready(mul_p_ready),
    .p_valid(mul_p_valid)
  );
  
  MulStream_sink sink (
    .clock(clock),
    .reset_n(reset_n),
    .mp(mul_p),
    .mp_ready(mul_p_ready),
    .mp_valid(mul_p_valid),
    .MulStream_p(p),
    .MulStream_p_valid(p_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //MulStream
