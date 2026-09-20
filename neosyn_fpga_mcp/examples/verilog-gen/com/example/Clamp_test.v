/**
 * Title      : Generated from com.example.Clamp_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Clamp_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Clamp_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire signed [31 : 0] driver_x;
  wire driver_x_valid;
  wire signed [31 : 0] driver_lo;
  wire driver_lo_valid;
  wire signed [31 : 0] driver_hi;
  wire driver_hi_valid;
  // Module : dut
  wire signed [31 : 0] dut_y;
  wire dut_y_valid;
  
  /**
   * Instances
   */
  Clamp_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .x(driver_x),
    .x_valid(driver_x_valid),
    .lo(driver_lo),
    .lo_valid(driver_lo_valid),
    .hi(driver_hi),
    .hi_valid(driver_hi_valid)
  );
  
  Clamp dut (
    .clock(clock),
    .reset_n(reset_n),
    .x(driver_x),
    .x_valid(driver_x_valid),
    .lo(driver_lo),
    .lo_valid(driver_lo_valid),
    .hi(driver_hi),
    .hi_valid(driver_hi_valid),
    .y(dut_y),
    .y_valid(dut_y_valid)
  );
  
  Clamp_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .y(dut_y),
    .y_valid(dut_y_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Clamp_test
