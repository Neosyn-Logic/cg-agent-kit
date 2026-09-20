/**
 * Title      : Generated from com.example.Recip_test_driver by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Recip_test_driver.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Recip_test_driver(input clock, input reset_n, output reg signed [31 : 0] d, output reg d_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Recip_test_driver
    if (~reset_n) begin
      d <= 32'b0;
      d_valid <= 1'b0;
    end else begin
      d_valid <= 1'b0;
      
      begin // line 33
        d <= 32'sh30000;
        d_valid <= 1'b1;
      end
    end
  end

endmodule //Recip_test_driver
