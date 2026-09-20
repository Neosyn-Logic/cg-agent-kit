/**
 * Title      : Generated from com.example.FixedSqrt_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.FixedSqrt_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module FixedSqrt_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire signed [31 : 0] driver_x;
  wire driver_x_valid;
  // Module : dut
  wire signed [31 : 0] dut_result;
  wire dut_result_valid;
  
  /**
   * Instances
   */
  FixedSqrt_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .x(driver_x),
    .x_valid(driver_x_valid)
  );
  
  FixedSqrt dut (
    .clock(clock),
    .reset_n(reset_n),
    .x(driver_x),
    .x_valid(driver_x_valid),
    .result(dut_result),
    .result_valid(dut_result_valid)
  );
  
  FixedSqrt_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .result(dut_result),
    .result_valid(dut_result_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //FixedSqrt_test
