/**
 * Title      : Generated from com.neosyn.examples.io.Manchester_test_driver by Neosyn IDE
 * Project    : home
 *
 * File       : com.neosyn.examples.io.Manchester_test_driver.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Manchester_test_driver(input clock, input reset_n, output reg  din, output reg din_valid);


  /**
   * State variables
   */
  
  
  
  /**
   * FSM
   */
  reg [3 : 0] FSM;
  
  localparam FSM_Manchester_test_driver = 4'b0000;
  localparam FSM_Manchester_test_driver_1 = 4'b0001;
  localparam FSM_Manchester_test_driver_2 = 4'b0010;
  localparam FSM_Manchester_test_driver_3 = 4'b0011;
  localparam FSM_Manchester_test_driver_4 = 4'b0100;
  localparam FSM_Manchester_test_driver_5 = 4'b0101;
  localparam FSM_Manchester_test_driver_6 = 4'b0110;
  localparam FSM_Manchester_test_driver_7 = 4'b0111;
  localparam FSM_Manchester_test_driver_8 = 4'b1000;
  localparam FSM_Manchester_test_driver_9 = 4'b1001;
  localparam FSM_Manchester_test_driver_10 = 4'b1010;
  localparam FSM_Manchester_test_driver_11 = 4'b1011;
  localparam FSM_Manchester_test_driver_12 = 4'b1100;
  localparam FSM_Manchester_test_driver_13 = 4'b1101;
  localparam FSM_Manchester_test_driver_14 = 4'b1110;
  localparam FSM_Manchester_test_driver_15 = 4'b1111;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Manchester_test_driver
    if (~reset_n) begin
      din <= 1'b0;
      din_valid <= 1'b0;
      FSM <= FSM_Manchester_test_driver;
    end else begin
      din_valid <= 1'b0;
      
      case (FSM)
        FSM_Manchester_test_driver: begin
          begin // line 175
            // 0xB2, MSB first, each bit held for
            din <= 1'b1;
            // 0xB2, MSB first, each bit held for
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_1;
          end
        end
      
        FSM_Manchester_test_driver_1: begin
          begin // line 175
            // 0xB2, MSB first, each bit held for
            din <= 1'b1;
            // 0xB2, MSB first, each bit held for
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_2;
          end
        end
      
        FSM_Manchester_test_driver_2: begin
          begin // line 176
            // its whole 2-cycle bit-time
            din <= 1'b0;
            // its whole 2-cycle bit-time
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_3;
          end
        end
      
        FSM_Manchester_test_driver_3: begin
          begin // line 176
            // its whole 2-cycle bit-time
            din <= 1'b0;
            // its whole 2-cycle bit-time
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_4;
          end
        end
      
        FSM_Manchester_test_driver_4: begin
          begin // line 177
            din <= 1'b1;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_5;
          end
        end
      
        FSM_Manchester_test_driver_5: begin
          begin // line 177
            din <= 1'b1;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_6;
          end
        end
      
        FSM_Manchester_test_driver_6: begin
          begin // line 178
            din <= 1'b1;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_7;
          end
        end
      
        FSM_Manchester_test_driver_7: begin
          begin // line 178
            din <= 1'b1;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_8;
          end
        end
      
        FSM_Manchester_test_driver_8: begin
          begin // line 179
            din <= 1'b0;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_9;
          end
        end
      
        FSM_Manchester_test_driver_9: begin
          begin // line 179
            din <= 1'b0;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_10;
          end
        end
      
        FSM_Manchester_test_driver_10: begin
          begin // line 180
            din <= 1'b0;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_11;
          end
        end
      
        FSM_Manchester_test_driver_11: begin
          begin // line 180
            din <= 1'b0;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_12;
          end
        end
      
        FSM_Manchester_test_driver_12: begin
          begin // line 181
            din <= 1'b1;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_13;
          end
        end
      
        FSM_Manchester_test_driver_13: begin
          begin // line 181
            din <= 1'b1;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_14;
          end
        end
      
        FSM_Manchester_test_driver_14: begin
          begin // line 182
            din <= 1'b0;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver_15;
          end
        end
      
        FSM_Manchester_test_driver_15: begin
          begin // line 182
            din <= 1'b0;
            din_valid <= 1'b1;
            FSM <= FSM_Manchester_test_driver;
          end
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //Manchester_test_driver
