/**
 * Title      : Generated from t.StreamDot_src by Neosyn IDE
 * Project    : home
 *
 * File       : t.StreamDot_src.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module StreamDot_src(input clock, input reset_n, input [31 : 0] StreamDot_a, input StreamDot_a_valid, input [31 : 0] StreamDot_b, input StreamDot_b_valid, output reg [31 : 0] fa, input fa_ready, output reg fa_valid, output reg [31 : 0] fb, input fb_ready, output reg fb_valid);


  /**
   * State variables
   */
  reg  stall;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of StreamDot_src
    if (~reset_n) begin
      stall <= 1'b0;
      fa <= 32'b0;
      fb <= 32'b0;
      fa_valid <= 1'b0;
      fb_valid <= 1'b0;
    end else begin
      fa_valid <= 1'b0;
      fb_valid <= 1'b0;
      
      // Hold each presented stream output; release only when every one of them has been taken.
      if (stall) begin
        fa_valid <= fa_valid;
        fb_valid <= fb_valid;
        if ((!fa_valid || fa_ready) && (!fb_valid || fb_ready)) begin
          stall <= 1'b0;
        end
      end
      // Always run the action scheduler so non-stream inputs (e.g. enqueues into a
      // queue with backpressured stream output) are not dropped while stalled.
      // Action guards ensure consume actions only fire when ready is asserted.
      if ((StreamDot_a_valid && StreamDot_b_valid)) begin // line 28
        fa <= StreamDot_a;
        fa_valid <= 1'b1;
        fb <= StreamDot_b;
        fb_valid <= 1'b1;
        stall <= (! (fa_ready) || ! (fb_ready));
      end else begin // line 0
      end
    end
  end

endmodule //StreamDot_src
