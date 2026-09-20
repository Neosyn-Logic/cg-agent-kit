/**
 * Title      : Generated from t.MulStream_feeder by Neosyn IDE
 * Project    : home
 *
 * File       : t.MulStream_feeder.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module MulStream_feeder(input clock, input reset_n, input signed [31 : 0] MulStream_a, input MulStream_a_valid, input signed [31 : 0] MulStream_b, input MulStream_b_valid, output reg signed [31 : 0] ma, input ma_ready, output reg ma_valid, output reg signed [31 : 0] mb, input mb_ready, output reg mb_valid);


  /**
   * State variables
   */
  reg  stall;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of MulStream_feeder
    if (~reset_n) begin
      stall <= 1'b0;
      ma <= 32'b0;
      mb <= 32'b0;
      ma_valid <= 1'b0;
      mb_valid <= 1'b0;
    end else begin
      ma_valid <= 1'b0;
      mb_valid <= 1'b0;
      
      // Hold each presented stream output; release only when every one of them has been taken.
      if (stall) begin
        ma_valid <= ma_valid;
        mb_valid <= mb_valid;
        if ((!ma_valid || ma_ready) && (!mb_valid || mb_ready)) begin
          stall <= 1'b0;
        end
      end
      // Always run the action scheduler so non-stream inputs (e.g. enqueues into a
      // queue with backpressured stream output) are not dropped while stalled.
      // Action guards ensure consume actions only fire when ready is asserted.
      if ((MulStream_a_valid && MulStream_b_valid)) begin // line 26
        ma <= MulStream_a;
        ma_valid <= 1'b1;
        mb <= MulStream_b;
        mb_valid <= 1'b1;
        stall <= (! (ma_ready) || ! (mb_ready));
      end else begin // line 0
      end
    end
  end

endmodule //MulStream_feeder
