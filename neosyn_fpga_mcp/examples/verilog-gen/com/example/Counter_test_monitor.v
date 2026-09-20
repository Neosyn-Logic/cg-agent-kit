/**
 * Title      : Generated from com.example.Counter_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Counter_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Counter_test_monitor(input clock, input reset_n, input [7 : 0] count, input count_valid);


  /**
   * State variables
   */
  reg  finished;
  reg [7 : 0] FSM_Counter_test_monitor_a_a;
  reg [7 : 0] FSM_Counter_test_monitor_1_a_b;
  reg [7 : 0] FSM_Counter_test_monitor_2_a_c;
  
  
  
  /**
   * FSM
   */
  reg [2 : 0] FSM;
  
  localparam FSM_Counter_test_monitor = 3'b000;
  localparam FSM_Counter_test_monitor_1 = 3'b001;
  localparam FSM_Counter_test_monitor_2 = 3'b010;
  localparam FSM_Counter_test_monitor_3 = 3'b011;
  localparam FSM_Counter_test_monitor_4 = 3'b100;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Counter_test_monitor
    if (~reset_n) begin
      finished <= 1'b0;
      FSM_Counter_test_monitor_a_a <= 8'b0;
      FSM_Counter_test_monitor_1_a_b <= 8'b0;
      FSM_Counter_test_monitor_2_a_c <= 8'b0;
      FSM <= FSM_Counter_test_monitor;
    end else begin
      
      case (FSM)
        FSM_Counter_test_monitor: begin
          if (count_valid) begin // line 21
            FSM_Counter_test_monitor_a_a <= count;
            FSM <= FSM_Counter_test_monitor_1;
          end
        end
      
        FSM_Counter_test_monitor_1: begin
          if (count_valid) begin // line 21
            FSM_Counter_test_monitor_1_a_b <= count;
            FSM <= FSM_Counter_test_monitor_2;
          end
        end
      
        FSM_Counter_test_monitor_2: begin
          if (count_valid) begin // line 22
            FSM_Counter_test_monitor_2_a_c <= count;
            FSM <= FSM_Counter_test_monitor_3;
          end
        end
      
        FSM_Counter_test_monitor_3: begin
          if (count_valid) begin // line 22
            // synthesis translate_off
            $display("count = %0h %0h %0h %0h\n", FSM_Counter_test_monitor_a_a, FSM_Counter_test_monitor_1_a_b, FSM_Counter_test_monitor_2_a_c, count);
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Counter_test_monitor_a_a == 8'h0))) begin
              $display("Assertion failed: (FSM_Counter_test_monitor_a_a == 8'h0)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Counter_test_monitor_1_a_b == 8'h1))) begin
              $display("Assertion failed: (FSM_Counter_test_monitor_1_a_b == 8'h1)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_Counter_test_monitor_2_a_c == 8'h2))) begin
              $display("Assertion failed: (FSM_Counter_test_monitor_2_a_c == 8'h2)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((count == 8'h3))) begin
              $display("Assertion failed: (count == 8'h3)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_Counter_test_monitor_4;
          end
        end
      
        FSM_Counter_test_monitor_4: begin
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Counter_test_monitor
