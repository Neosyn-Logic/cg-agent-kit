/**
 * Title      : Generated from com.example.Tee2_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Tee2_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Tee2_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire signed [31 : 0] driver_a;
  wire driver_a_valid;
  // Module : dut
  wire signed [31 : 0] dut_y0;
  wire dut_y0_valid;
  wire signed [31 : 0] dut_y1;
  wire dut_y1_valid;
  
  /**
   * Instances
   */
  Tee2_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .a(driver_a),
    .a_valid(driver_a_valid)
  );
  
  Tee2 dut (
    .clock(clock),
    .reset_n(reset_n),
    .a(driver_a),
    .a_valid(driver_a_valid),
    .y0(dut_y0),
    .y0_valid(dut_y0_valid),
    .y1(dut_y1),
    .y1_valid(dut_y1_valid)
  );
  
  Tee2_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .y0(dut_y0),
    .y0_valid(dut_y0_valid),
    .y1(dut_y1),
    .y1_valid(dut_y1_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Tee2_test
