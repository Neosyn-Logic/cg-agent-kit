/**
 * Title      : Generated from com.example.Lerp_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Lerp_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Lerp_test_monitor(input clock, input reset_n, input signed [31 : 0] y, input y_valid);


  /**
   * State variables
   */
  reg  finished;
  
  
  
  /**
   * FSM
   */
  reg FSM;
  
  localparam FSM_Lerp_test_monitor = 1'b0;
  localparam FSM_Lerp_test_monitor_1 = 1'b1;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Lerp_test_monitor
    if (~reset_n) begin
      finished <= 1'b0;
      FSM <= FSM_Lerp_test_monitor;
    end else begin
      
      case (FSM)
        FSM_Lerp_test_monitor: begin
          if (y_valid) begin // line 25
            // synthesis translate_off
            $display("lerp=%0h (expect 196608=3.0)\n", y);
            // synthesis translate_on
            // synthesis translate_off
            if (~((y == 32'sh30000))) begin
              $display("Assertion failed: (y == 32'sh30000)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_Lerp_test_monitor_1;
          end
        end
      
        FSM_Lerp_test_monitor_1: begin
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Lerp_test_monitor
