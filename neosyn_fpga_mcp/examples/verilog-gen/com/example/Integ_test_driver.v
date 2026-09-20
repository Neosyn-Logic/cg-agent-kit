/**
 * Title      : Generated from com.example.Integ_test_driver by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Integ_test_driver.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Integ_test_driver(input clock, input reset_n, output reg signed [31 : 0] acc, output reg acc_valid);


  /**
   * State variables
   */
  
  
  
  /**
   * FSM
   */
  reg [1 : 0] FSM;
  
  localparam FSM_Integ_test_driver = 2'b00;
  localparam FSM_Integ_test_driver_1 = 2'b01;
  localparam FSM_Integ_test_driver_2 = 2'b10;
  localparam FSM_Integ_test_driver_3 = 2'b11;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Integ_test_driver
    if (~reset_n) begin
      acc <= 32'b0;
      acc_valid <= 1'b0;
      FSM <= FSM_Integ_test_driver;
    end else begin
      acc_valid <= 1'b0;
      
      case (FSM)
        FSM_Integ_test_driver: begin
          begin // line 18
            acc <= 32'sh10000;
            acc_valid <= 1'b1;
            FSM <= FSM_Integ_test_driver_1;
          end
        end
      
        FSM_Integ_test_driver_1: begin
          begin // line 18
            acc <= 32'sh10000;
            acc_valid <= 1'b1;
            FSM <= FSM_Integ_test_driver_2;
          end
        end
      
        FSM_Integ_test_driver_2: begin
          begin // line 18
            acc <= 32'sh10000;
            acc_valid <= 1'b1;
            FSM <= FSM_Integ_test_driver_3;
          end
        end
      
        FSM_Integ_test_driver_3: begin
          begin // line 18
            acc <= 32'sh10000;
            acc_valid <= 1'b1;
            FSM <= FSM_Integ_test_driver;
          end
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Integ_test_driver
