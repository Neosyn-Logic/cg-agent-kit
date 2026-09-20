/**
 * Title      : Generated from com.example.FifoPipe_producer by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.FifoPipe_producer.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module FifoPipe_producer(input clock, input reset_n, output reg [7 : 0] dout, input dout_ready, output reg dout_valid);


  /**
   * State variables
   */
  reg [7 : 0] n;
  reg  stall;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of FifoPipe_producer
    if (~reset_n) begin
      n <= 8'h0;
      stall <= 1'b0;
      dout <= 8'b0;
      dout_valid <= 1'b0;
    end else begin
      dout_valid <= 1'b0;
      
      // Hold each presented stream output; release only when every one of them has been taken.
      if (stall) begin
        dout_valid <= dout_valid;
        if ((!dout_valid || dout_ready)) begin
          stall <= 1'b0;
        end
      end
      // Always run the action scheduler so non-stream inputs (e.g. enqueues into a
      // queue with backpressured stream output) are not dropped while stalled.
      // Action guards ensure consume actions only fire when ready is asserted.
      begin : FSM_FifoPipe_producer_a // line 16
        reg [8 : 0] orion;
        reg [8 : 0] lyra;
      
        orion = (n + 8'h1);
        dout <= orion[7 : 0];
        dout_valid <= 1'b1;
        lyra = (n + 8'h1);
        n <= lyra[7 : 0];
        stall <= ! (dout_ready);
      end
    end
  end

endmodule //FifoPipe_producer
