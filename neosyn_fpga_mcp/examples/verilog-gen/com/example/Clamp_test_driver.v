/**
 * Title      : Generated from com.example.Clamp_test_driver by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Clamp_test_driver.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Clamp_test_driver(input clock, input reset_n, output reg signed [31 : 0] x, output reg x_valid, output reg signed [31 : 0] lo, output reg lo_valid, output reg signed [31 : 0] hi, output reg hi_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Clamp_test_driver
    if (~reset_n) begin
      x <= 32'b0;
      lo <= 32'b0;
      hi <= 32'b0;
      x_valid <= 1'b0;
      lo_valid <= 1'b0;
      hi_valid <= 1'b0;
    end else begin
      x_valid <= 1'b0;
      lo_valid <= 1'b0;
      hi_valid <= 1'b0;
      
      begin // line 23
        x <= 32'sh50000;
        x_valid <= 1'b1;
        lo <= 32'sh10000;
        lo_valid <= 1'b1;
        hi <= 32'sh30000;
        hi_valid <= 1'b1;
      end
    end
  end

endmodule //Clamp_test_driver
