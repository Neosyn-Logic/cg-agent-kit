/**
 * Title      : Generated from com.example.Tee2_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Tee2_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Tee2_test_monitor(input clock, input reset_n, input signed [31 : 0] y0, input y0_valid, input signed [31 : 0] y1, input y1_valid);


  /**
   * State variables
   */
  reg  finished;
  
  
  
  /**
   * FSM
   */
  reg FSM;
  
  localparam FSM_Tee2_test_monitor = 1'b0;
  localparam FSM_Tee2_test_monitor_1 = 1'b1;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Tee2_test_monitor
    if (~reset_n) begin
      finished <= 1'b0;
      FSM <= FSM_Tee2_test_monitor;
    end else begin
      
      case (FSM)
        FSM_Tee2_test_monitor: begin
          if ((y0_valid && y1_valid)) begin // line 29
            // synthesis translate_off
            $display("tee y0=%0h y1=%0h expect 7,7\n", y0, y1);
            // synthesis translate_on
            // synthesis translate_off
            if (~((y0 == 32'sh7))) begin
              $display("Assertion failed: (y0 == 32'sh7)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((y1 == 32'sh7))) begin
              $display("Assertion failed: (y1 == 32'sh7)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_Tee2_test_monitor_1;
          end
        end
      
        FSM_Tee2_test_monitor_1: begin
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Tee2_test_monitor
