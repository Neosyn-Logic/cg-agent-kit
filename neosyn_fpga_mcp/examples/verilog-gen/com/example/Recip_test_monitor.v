/**
 * Title      : Generated from com.example.Recip_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Recip_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Recip_test_monitor(input clock, input reset_n, input signed [31 : 0] inv, input inv_valid);


  /**
   * State variables
   */
  reg  finished;
  
  
  
  /**
   * FSM
   */
  reg FSM;
  
  localparam FSM_Recip_test_monitor = 1'b0;
  localparam FSM_Recip_test_monitor_1 = 1'b1;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Recip_test_monitor
    if (~reset_n) begin
      finished <= 1'b0;
      FSM <= FSM_Recip_test_monitor;
    end else begin
      
      case (FSM)
        FSM_Recip_test_monitor: begin
          if (inv_valid) begin // line 37
            // synthesis translate_off
            $display("1/d = %0h (expect 21845 = 0.3333 Q16.16)\n", inv);
            // synthesis translate_on
            // synthesis translate_off
            if (~((inv == 32'sh5555))) begin
              $display("Assertion failed: (inv == 32'sh5555)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_Recip_test_monitor_1;
          end
        end
      
        FSM_Recip_test_monitor_1: begin
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Recip_test_monitor
