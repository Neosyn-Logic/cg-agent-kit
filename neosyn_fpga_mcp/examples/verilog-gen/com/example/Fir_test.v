/**
 * Title      : Generated from com.example.Fir_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Fir_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Fir_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire signed [31 : 0] driver_x;
  wire driver_x_valid;
  // Module : dut
  wire signed [31 : 0] dut_y;
  wire dut_y_valid;
  
  /**
   * Instances
   */
  Fir_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .x(driver_x),
    .x_valid(driver_x_valid)
  );
  
  Fir dut (
    .clock(clock),
    .reset_n(reset_n),
    .x(driver_x),
    .x_valid(driver_x_valid),
    .y(dut_y),
    .y_valid(dut_y_valid)
  );
  
  Fir_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .y(dut_y),
    .y_valid(dut_y_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Fir_test
