
/**
 * Running total — the accumulator, the simplest stateful datapath there is and
 * the shape behind every integrator, moving sum, packet-byte counter and
 * dot-product partial.
 * 
 * ONE register, updated every cycle: `acc = acc + x`. Everything harder (FIR,
 * MAC, dot product) is this loop with a multiply in front of it.
 * 
 * Timing, which is the only subtle part: an `out sync` write lands in the SAME
 * cycle as the reads, so writing AFTER the update publishes the total that
 * INCLUDES this cycle's input (1, 3, 6, …). Swap the two lines and you publish
 * the previous total instead — a one-cycle lag that is sometimes what you want
 * (a delayed/registered sum) and is the usual off-by-one in this block.
 * 
 * `acc` is inline-initialised rather than set in setup(): a setup() would add a
 * reset state and offset the whole stream by a cycle.
 * 
 * TO ADAPT:
 * * saturating instead of wrapping — clamp before the write (see Clamp)
 * * a moving sum over N — subtract the sample leaving the window
 * * an integrator with a leak — `acc = acc - (acc >> k) + x`
 * * MAC / dot product — accumulate `a*b` instead of `x` (see StreamDot)
 * 
 * `sum` is u16 while `x` is u8: the accumulator MUST be wider than its input or
 * it wraps. Widen both together for longer runs.
 */
module Accumulator(input clock, input reset_n, input [7 : 0] x, input x_valid, output reg [15 : 0] sum, output reg sum_valid);


  /**
   * State variables
   */
  reg [15 : 0] acc;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Accumulator
    if (~reset_n) begin
      acc <= 16'h0;
      sum <= 16'b0;
      sum_valid <= 1'b0;
    end else begin
      sum_valid <= 1'b0;
      
      if (x_valid) begin : FSM_Accumulator_a // line 41
        reg [16 : 0] orion;
        reg [16 : 0] lyra;
      
        orion = (acc + x);
        sum <= orion[15 : 0];
        sum_valid <= 1'b1;
        lyra = (acc + x);
        acc <= lyra[15 : 0];
      end
    end
  end

endmodule //Accumulator
