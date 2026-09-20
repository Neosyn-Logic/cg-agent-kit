/**
 * Title      : Generated from com.example.Fir_test_driver by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Fir_test_driver.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Fir_test_driver(input clock, input reset_n, output reg signed [31 : 0] x, output reg x_valid);


  /**
   * State variables
   */
  
  
  
  /**
   * FSM
   */
  reg [2 : 0] FSM;
  
  localparam FSM_Fir_test_driver = 3'b000;
  localparam FSM_Fir_test_driver_1 = 3'b001;
  localparam FSM_Fir_test_driver_2 = 3'b010;
  localparam FSM_Fir_test_driver_3 = 3'b011;
  localparam FSM_Fir_test_driver_4 = 3'b100;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Fir_test_driver
    if (~reset_n) begin
      x <= 32'b0;
      x_valid <= 1'b0;
      FSM <= FSM_Fir_test_driver;
    end else begin
      x_valid <= 1'b0;
      
      case (FSM)
        FSM_Fir_test_driver: begin
          begin // line 20
            x <= 32'sh10000;
            x_valid <= 1'b1;
            FSM <= FSM_Fir_test_driver_1;
          end
        end
      
        FSM_Fir_test_driver_1: begin
          begin // line 20
            x <= 32'sh20000;
            x_valid <= 1'b1;
            FSM <= FSM_Fir_test_driver_2;
          end
        end
      
        FSM_Fir_test_driver_2: begin
          begin // line 20
            x <= 32'sh30000;
            x_valid <= 1'b1;
            FSM <= FSM_Fir_test_driver_3;
          end
        end
      
        FSM_Fir_test_driver_3: begin
          begin // line 20
            x <= 32'sh40000;
            x_valid <= 1'b1;
            FSM <= FSM_Fir_test_driver_4;
          end
        end
      
        FSM_Fir_test_driver_4: begin
          begin // line 20
            x <= 32'sh50000;
            x_valid <= 1'b1;
            FSM <= FSM_Fir_test_driver;
          end
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Fir_test_driver
