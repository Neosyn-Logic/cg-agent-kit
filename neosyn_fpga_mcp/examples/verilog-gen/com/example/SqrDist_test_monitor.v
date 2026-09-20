/**
 * Title      : Generated from com.example.SqrDist_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.SqrDist_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module SqrDist_test_monitor(input clock, input reset_n, input signed [31 : 0] result, input result_valid);


  /**
   * State variables
   */
  reg  finished;
  
  
  
  /**
   * FSM
   */
  reg FSM;
  
  localparam FSM_SqrDist_test_monitor = 1'b0;
  localparam FSM_SqrDist_test_monitor_1 = 1'b1;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of SqrDist_test_monitor
    if (~reset_n) begin
      finished <= 1'b0;
      FSM <= FSM_SqrDist_test_monitor;
    end else begin
      
      case (FSM)
        FSM_SqrDist_test_monitor: begin
          if (result_valid) begin // line 44
            // synthesis translate_off
            $display("sqrDist = %0h (expect 491520 = 7.5 Q16.16)\n", result);
            // synthesis translate_on
            // synthesis translate_off
            if (~((result == 32'sh78000))) begin
              $display("Assertion failed: (result == 32'sh78000)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_SqrDist_test_monitor_1;
          end
        end
      
        FSM_SqrDist_test_monitor_1: begin
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //SqrDist_test_monitor
