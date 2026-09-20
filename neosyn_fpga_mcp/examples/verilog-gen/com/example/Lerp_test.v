/**
 * Title      : Generated from com.example.Lerp_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Lerp_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Lerp_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire signed [31 : 0] driver_a;
  wire driver_a_valid;
  wire signed [31 : 0] driver_b;
  wire driver_b_valid;
  wire signed [31 : 0] driver_t;
  wire driver_t_valid;
  // Module : dut
  wire signed [31 : 0] dut_y;
  wire dut_y_valid;
  
  /**
   * Instances
   */
  Lerp_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .a(driver_a),
    .a_valid(driver_a_valid),
    .b(driver_b),
    .b_valid(driver_b_valid),
    .t(driver_t),
    .t_valid(driver_t_valid)
  );
  
  Lerp dut (
    .clock(clock),
    .reset_n(reset_n),
    .a(driver_a),
    .a_valid(driver_a_valid),
    .b(driver_b),
    .b_valid(driver_b_valid),
    .t(driver_t),
    .t_valid(driver_t_valid),
    .y(dut_y),
    .y_valid(dut_y_valid)
  );
  
  Lerp_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .y(dut_y),
    .y_valid(dut_y_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Lerp_test
