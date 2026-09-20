/**
 * Title      : Generated from com.example.Divide_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Divide_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Divide_test_monitor(input clock, input reset_n, input signed [31 : 0] q, input q_valid);


  /**
   * State variables
   */
  reg  finished;
  
  
  
  /**
   * FSM
   */
  reg FSM;
  
  localparam FSM_Divide_test_monitor = 1'b0;
  localparam FSM_Divide_test_monitor_1 = 1'b1;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Divide_test_monitor
    if (~reset_n) begin
      finished <= 1'b0;
      FSM <= FSM_Divide_test_monitor;
    end else begin
      
      case (FSM)
        FSM_Divide_test_monitor: begin
          if (q_valid) begin // line 20
            // synthesis translate_off
            $display("a/b=%0h (expect 196608)\n", q);
            // synthesis translate_on
            // synthesis translate_off
            if (~((q == 32'sh30000))) begin
              $display("Assertion failed: (q == 32'sh30000)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_Divide_test_monitor_1;
          end
        end
      
        FSM_Divide_test_monitor_1: begin
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Divide_test_monitor
