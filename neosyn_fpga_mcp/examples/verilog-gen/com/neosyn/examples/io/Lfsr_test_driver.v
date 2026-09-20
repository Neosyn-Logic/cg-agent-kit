/**
 * Title      : Generated from com.neosyn.examples.io.Lfsr_test_driver by Neosyn IDE
 * Project    : home
 *
 * File       : com.neosyn.examples.io.Lfsr_test_driver.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Lfsr_test_driver(input clock, input reset_n, output reg  en, output reg en_valid, output reg  reseed, output reg reseed_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Lfsr_test_driver
    if (~reset_n) begin
      en <= 1'b0;
      reseed <= 1'b0;
      en_valid <= 1'b0;
      reseed_valid <= 1'b0;
    end else begin
      en_valid <= 1'b0;
      reseed_valid <= 1'b0;
      
      begin // line 107
        en <= 1'b1;
        en_valid <= 1'b1;
        reseed <= 1'b0;
        reseed_valid <= 1'b1;
      end
    end
  end

endmodule //Lfsr_test_driver
