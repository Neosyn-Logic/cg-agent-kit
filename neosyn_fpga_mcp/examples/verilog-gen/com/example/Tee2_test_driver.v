/**
 * Title      : Generated from com.example.Tee2_test_driver by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Tee2_test_driver.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Tee2_test_driver(input clock, input reset_n, output reg signed [31 : 0] a, output reg a_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Tee2_test_driver
    if (~reset_n) begin
      a <= 32'b0;
      a_valid <= 1'b0;
    end else begin
      a_valid <= 1'b0;
      
      begin // line 25
        a <= 32'sh7;
        a_valid <= 1'b1;
      end
    end
  end

endmodule //Tee2_test_driver
