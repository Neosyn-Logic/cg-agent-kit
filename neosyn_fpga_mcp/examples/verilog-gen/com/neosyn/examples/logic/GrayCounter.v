
/**
 * Gray-code counter, with the binary <-> Gray conversion both ways AND a hardware
 * check of the property that is the whole reason Gray code exists.
 * 
 * THE PROPERTY: consecutive Gray codes differ in EXACTLY ONE BIT. Binary does
 * not — 0111 -> 1000 changes all four. That matters whenever a multi-bit value
 * is sampled by something that is not synchronous to the counter, because the
 * sampler can catch the word mid-transition and see a mixture of the old and new
 * bits. With binary, 7 -> 8 sampled at the wrong instant can read as 15 or 0 —
 * a value the counter never held. With Gray only one bit is ever in flight, so
 * the worst case is reading the old value or the new one. Both are legal.
 * 
 * THAT IS THE CDC FIFO POINTER RULE, and it is not theoretical: this project
 * shipped a VHDL `AsynchronousFIFO` that crossed BINARY pointers into the far
 * domain and could compute a bogus occupancy for exactly this reason. The fix
 * was Gray-coding the pointers (plus a 2-flop synchroniser on the far side).
 * If you are building a dual-clock FIFO, prefer `std.fifo.AsynchronousFIFO` —
 * it already does this — and use this block when you need the pointer yourself,
 * or for a shaft/position encoder, or a low-power bus where one toggling bit per
 * step is the point.
 * 
 * THE CONVERSIONS, both one line:
 * binary -> Gray:  g = b ^ (b >> 1)                     (one XOR per bit)
 * Gray -> binary:  b = g ^ (g>>1) ^ (g>>2) ^ (g>>3)     (an XOR PREFIX)
 * The decode is a prefix-XOR, so it costs W-1 levels for a W-bit word — a
 * combinational chain that gets slow when W is large. That is why real designs
 * keep the counter in BINARY and derive Gray for the crossing (as here), rather
 * than counting in Gray and decoding on every use.
 * 
 * `onestep` is the property CHECKED IN HARDWARE: it compares this cycle's Gray
 * word with last cycle's and asserts the difference is a single bit, using the
 * standard power-of-two test `d != 0 && (d & (d-1)) == 0`. The test vectors pin
 * it high on every cycle that follows an increment — including the 15 -> 0 wrap,
 * which is the case a naive Gray implementation gets wrong. `onestep` is low
 * while `en` is low, because no step happened; it is a check on INCREMENTS, not
 * a permanent property of the wire.
 * 
 * TO ADAPT:
 * * other widths — everything scales; the decode needs one more XOR term per
 * bit (u8 wants >>1 >>2 >>3 >>4 >>5 >>6 >>7, or a two-stage prefix tree).
 * A Gray counter is only single-bit-change if the count is a power of two
 * long: a mod-10 Gray counter needs a hand-built sequence.
 * * a CDC pointer — take `gray` into the other domain through
 * `std.lib.SynchronizerFF` (one instance per bit), and decode there.
 * * an absolute POSITION ENCODER — the disc reads out Gray directly; you only
 * need the decode half of this block.
 * * one-hot / thermometer coding — different property (one bit set / a run of
 * set bits) but the same "publish a code, decode it back" skeleton.
 * 
 * Timing (as in every Cg FSM): a port reflects the register at the START of the
 * cycle, so publish the CURRENT count and its Gray code BEFORE incrementing. All
 * registers are inline-initialized (no setup(), which would add a reset state
 * that offsets the whole stream).
 */
module GrayCounter(input clock, input reset_n, input  en, input en_valid, output reg [3 : 0] bin, output reg bin_valid, output reg [3 : 0] gray, output reg gray_valid, output reg [3 : 0] decoded, output reg decoded_valid, output reg  onestep, output reg onestep_valid);


  /**
   * State variables
   */
  reg [3 : 0] b;
  reg [3 : 0] gprev;
  reg  stepped;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of GrayCounter
    if (~reset_n) begin
      b <= 4'h0;
      gprev <= 4'h0;
      stepped <= 1'b0;
      bin <= 4'b0;
      gray <= 4'b0;
      decoded <= 4'b0;
      onestep <= 1'b0;
      bin_valid <= 1'b0;
      gray_valid <= 1'b0;
      decoded_valid <= 1'b0;
      onestep_valid <= 1'b0;
    end else begin
      bin_valid <= 1'b0;
      gray_valid <= 1'b0;
      decoded_valid <= 1'b0;
      onestep_valid <= 1'b0;
      
      if (en_valid) begin : FSM_GrayCounter_a // line 85
        reg [3 : 0] b_0_3;
        reg [4 : 0] orion;
        reg [4 : 0] lyra;
      
        bin <= b;
        bin_valid <= 1'b1;
        // publish the CURRENT
        gray <= (b ^ (b >> 4'h1));
        // publish the CURRENT
        gray_valid <= 1'b1;
        // state, before the
        decoded <= ((((b ^ (b >> 4'h1)) ^ ((b ^ (b >> 4'h1)) >> 4'h1)) ^ ((b ^ (b >> 4'h1)) >> 4'h2)) ^ ((b ^ (b >> 4'h1)) >> 4'h3));
        // state, before the
        decoded_valid <= 1'b1;
        orion = (((b ^ (b >> 4'h1)) ^ gprev) - 4'h1);
        // transition
        onestep <= ((stepped && (((b ^ (b >> 4'h1)) ^ gprev) != 4'h0)) && ((((b ^ (b >> 4'h1)) ^ gprev) & orion[3 : 0]) == 4'h0));
        // transition
        onestep_valid <= 1'b1;
        if (en) begin
          lyra = (b + 4'h1);
          b_0_3 = lyra[3 : 0];
        end else begin
          b_0_3 = b;
        end
        b <= b_0_3;
        gprev <= (b ^ (b >> 4'h1));
        stepped <= en;
      end
    end
  end

endmodule //GrayCounter
