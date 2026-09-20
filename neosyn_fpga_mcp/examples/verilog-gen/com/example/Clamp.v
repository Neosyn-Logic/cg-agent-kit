
/**
 * Clamp — saturate x to the range [lo, hi], Q16.16 (signed). PORT-DRIVEN so the
 * two comparators + selects survive synthesis. The canonical DSP/control/graphics
 * guard against overflow wrap and out-of-range values. Verified: sim ok, REAL.
 */
module Clamp(input clock, input reset_n, input signed [31 : 0] x, input x_valid, input signed [31 : 0] lo, input lo_valid, input signed [31 : 0] hi, input hi_valid, output reg signed [31 : 0] y, output reg y_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Clamp
    if (~reset_n) begin
      y <= 32'b0;
      y_valid <= 1'b0;
    end else begin
      y_valid <= 1'b0;
      
      if (((x_valid && lo_valid) && hi_valid)) begin : FSM_Clamp_a // line 10
        reg signed [31 : 0] r_3;
        reg signed [31 : 0] r_5;
      
        if ((x < lo)) begin
          r_3 = lo;
        end else begin
          r_3 = x;
        end
        if ((x > hi)) begin
          r_5 = hi;
        end else begin
          r_5 = r_3;
        end
        y <= r_5;
        y_valid <= 1'b1;
      end
    end
  end

endmodule //Clamp
