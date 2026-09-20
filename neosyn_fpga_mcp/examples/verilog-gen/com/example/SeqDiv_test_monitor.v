/**
 * Title      : Generated from com.example.SeqDiv_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.SeqDiv_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module SeqDiv_test_monitor(input clock, input reset_n, input signed [31 : 0] q, input q_valid);


  /**
   * State variables
   */
  reg  finished;
  
  
  
  /**
   * FSM
   */
  reg FSM;
  
  localparam FSM_SeqDiv_test_monitor = 1'b0;
  localparam FSM_SeqDiv_test_monitor_1 = 1'b1;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of SeqDiv_test_monitor
    if (~reset_n) begin
      finished <= 1'b0;
      FSM <= FSM_SeqDiv_test_monitor;
    end else begin
      
      case (FSM)
        FSM_SeqDiv_test_monitor: begin
          if (q_valid) begin // line 26
            // synthesis translate_off
            $display("seqdiv a/b=%0h (expect 196608)\n", q);
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_SeqDiv_test_monitor_1;
          end
        end
      
        FSM_SeqDiv_test_monitor_1: begin
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //SeqDiv_test_monitor
