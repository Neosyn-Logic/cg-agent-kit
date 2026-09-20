/**
 * Title      : Generated from com.example.Fir_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Fir_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Fir_test_monitor(input clock, input reset_n, input signed [31 : 0] y, input y_valid);


  /**
   * State variables
   */
  reg  finished;
  reg signed [31 : 0] FSM_Fir_test_monitor_a_y0;
  reg signed [31 : 0] FSM_Fir_test_monitor_1_a_y1;
  reg signed [31 : 0] FSM_Fir_test_monitor_2_a_y2;
  reg signed [31 : 0] FSM_Fir_test_monitor_3_a_y3;
  
  
  
  /**
   * FSM
   */
  reg [2 : 0] FSM;
  
  localparam FSM_Fir_test_monitor = 3'b000;
  localparam FSM_Fir_test_monitor_1 = 3'b001;
  localparam FSM_Fir_test_monitor_2 = 3'b010;
  localparam FSM_Fir_test_monitor_3 = 3'b011;
  localparam FSM_Fir_test_monitor_4 = 3'b100;
  localparam FSM_Fir_test_monitor_5 = 3'b101;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Fir_test_monitor
    if (~reset_n) begin
      finished <= 1'b0;
      FSM_Fir_test_monitor_a_y0 <= 32'b0;
      FSM_Fir_test_monitor_1_a_y1 <= 32'b0;
      FSM_Fir_test_monitor_2_a_y2 <= 32'b0;
      FSM_Fir_test_monitor_3_a_y3 <= 32'b0;
      FSM <= FSM_Fir_test_monitor;
    end else begin
      
      case (FSM)
        FSM_Fir_test_monitor: begin
          if (y_valid) begin // line 22
            FSM_Fir_test_monitor_a_y0 <= y;
            FSM <= FSM_Fir_test_monitor_1;
          end
        end
      
        FSM_Fir_test_monitor_1: begin
          if (y_valid) begin // line 22
            FSM_Fir_test_monitor_1_a_y1 <= y;
            FSM <= FSM_Fir_test_monitor_2;
          end
        end
      
        FSM_Fir_test_monitor_2: begin
          if (y_valid) begin // line 22
            FSM_Fir_test_monitor_2_a_y2 <= y;
            FSM <= FSM_Fir_test_monitor_3;
          end
        end
      
        FSM_Fir_test_monitor_3: begin
          if (y_valid) begin // line 22
            FSM_Fir_test_monitor_3_a_y3 <= y;
            FSM <= FSM_Fir_test_monitor_4;
          end
        end
      
        FSM_Fir_test_monitor_4: begin
          if (y_valid) begin // line 22
            // synthesis translate_off
            $display("fir done\n");
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Fir_test_monitor_a_y0 == 32'sh999a))) begin
              $display("Assertion failed: (FSM_Fir_test_monitor_a_y0 == 32'sh999a)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Fir_test_monitor_1_a_y1 == 32'sh18001))) begin
              $display("Assertion failed: (FSM_Fir_test_monitor_1_a_y1 == 32'sh18001)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Fir_test_monitor_2_a_y2 == 32'sh28cce))) begin
              $display("Assertion failed: (FSM_Fir_test_monitor_2_a_y2 == 32'sh28cce)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Fir_test_monitor_3_a_y3 == 32'sh3a668))) begin
              $display("Assertion failed: (FSM_Fir_test_monitor_3_a_y3 == 32'sh3a668)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((y == 32'sh4c002))) begin
              $display("Assertion failed: (y == 32'sh4c002)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_Fir_test_monitor_5;
          end
        end
      
        FSM_Fir_test_monitor_5: begin
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Fir_test_monitor
