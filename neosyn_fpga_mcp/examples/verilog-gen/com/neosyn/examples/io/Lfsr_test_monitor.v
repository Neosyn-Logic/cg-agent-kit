/**
 * Title      : Generated from com.neosyn.examples.io.Lfsr_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.neosyn.examples.io.Lfsr_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Lfsr_test_monitor(input clock, input reset_n, input [7 : 0] prbs, input prbs_valid);

  `include "Lfsr_pkg.v"

  /**
   * State variables
   */
  reg [15 : 0] n;
  reg  finished;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Lfsr_test_monitor
    if (~reset_n) begin
      n <= 16'h0;
      finished <= 1'b0;
    end else begin
      
      if (prbs_valid) begin : FSM_Lfsr_test_monitor_a // line 115
        reg [16 : 0] orion;
      
        // synthesis translate_off
        if (~((prbs != 8'h0))) begin
          $display("Assertion failed: (prbs != 8'h0)");
          $stop;
        end
        // synthesis translate_on
        // all-zero is the dead fixed point
        if (((n != 16'h0) && (prbs == LFSR_SEED))) begin
          // synthesis translate_off
          $display("LFSR period = %0h (expect 255)\n", n);
          // synthesis translate_on
          // synthesis translate_off
          if (~((n == 16'hff))) begin
            $display("Assertion failed: (n == 16'hff)");
            $stop;
          end
          // synthesis translate_on
          // 2^8 - 1: maximal length
          finished <= 1'b1;
        end
        orion = (n + 16'h1);
        n <= orion[15 : 0];
      end
    end
  end

endmodule //Lfsr_test_monitor
