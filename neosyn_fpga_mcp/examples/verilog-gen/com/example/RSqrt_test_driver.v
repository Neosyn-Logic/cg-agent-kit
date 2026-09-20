/**
 * Title      : Generated from com.example.RSqrt_test_driver by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.RSqrt_test_driver.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module RSqrt_test_driver(input clock, input reset_n, output reg signed [31 : 0] x, output reg x_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of RSqrt_test_driver
    if (~reset_n) begin
      x <= 32'b0;
      x_valid <= 1'b0;
    end else begin
      x_valid <= 1'b0;
      
      begin // line 33
        x <= 32'sh40000;
        x_valid <= 1'b1;
      end
    end
  end

endmodule //RSqrt_test_driver
