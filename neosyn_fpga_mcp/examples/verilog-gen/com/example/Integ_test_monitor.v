/**
 * Title      : Generated from com.example.Integ_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Integ_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Integ_test_monitor(input clock, input reset_n, input signed [31 : 0] pos, input pos_valid);


  /**
   * State variables
   */
  reg  finished;
  reg signed [31 : 0] FSM_Integ_test_monitor_a_p0;
  reg signed [31 : 0] FSM_Integ_test_monitor_1_a_p1;
  reg signed [31 : 0] FSM_Integ_test_monitor_2_a_p2;
  
  
  
  /**
   * FSM
   */
  reg [2 : 0] FSM;
  
  localparam FSM_Integ_test_monitor = 3'b000;
  localparam FSM_Integ_test_monitor_1 = 3'b001;
  localparam FSM_Integ_test_monitor_2 = 3'b010;
  localparam FSM_Integ_test_monitor_3 = 3'b011;
  localparam FSM_Integ_test_monitor_4 = 3'b100;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Integ_test_monitor
    if (~reset_n) begin
      finished <= 1'b0;
      FSM_Integ_test_monitor_a_p0 <= 32'b0;
      FSM_Integ_test_monitor_1_a_p1 <= 32'b0;
      FSM_Integ_test_monitor_2_a_p2 <= 32'b0;
      FSM <= FSM_Integ_test_monitor;
    end else begin
      
      case (FSM)
        FSM_Integ_test_monitor: begin
          if (pos_valid) begin // line 20
            FSM_Integ_test_monitor_a_p0 <= pos;
            FSM <= FSM_Integ_test_monitor_1;
          end
        end
      
        FSM_Integ_test_monitor_1: begin
          if (pos_valid) begin // line 20
            FSM_Integ_test_monitor_1_a_p1 <= pos;
            FSM <= FSM_Integ_test_monitor_2;
          end
        end
      
        FSM_Integ_test_monitor_2: begin
          if (pos_valid) begin // line 20
            FSM_Integ_test_monitor_2_a_p2 <= pos;
            FSM <= FSM_Integ_test_monitor_3;
          end
        end
      
        FSM_Integ_test_monitor_3: begin
          if (pos_valid) begin // line 20
            // synthesis translate_off
            $display("integ done\n");
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Integ_test_monitor_a_p0 == 32'sh4000))) begin
              $display("Assertion failed: (FSM_Integ_test_monitor_a_p0 == 32'sh4000)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Integ_test_monitor_1_a_p1 == 32'shc000))) begin
              $display("Assertion failed: (FSM_Integ_test_monitor_1_a_p1 == 32'shc000)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Integ_test_monitor_2_a_p2 == 32'sh18000))) begin
              $display("Assertion failed: (FSM_Integ_test_monitor_2_a_p2 == 32'sh18000)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((pos == 32'sh28000))) begin
              $display("Assertion failed: (pos == 32'sh28000)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_Integ_test_monitor_4;
          end
        end
      
        FSM_Integ_test_monitor_4: begin
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Integ_test_monitor
