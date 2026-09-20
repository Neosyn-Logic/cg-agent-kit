/**
 * Title      : Generated from com.example.Distance_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Distance_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Distance_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire signed [31 : 0] driver_a0;
  wire driver_a0_valid;
  wire signed [31 : 0] driver_a1;
  wire driver_a1_valid;
  wire signed [31 : 0] driver_a2;
  wire driver_a2_valid;
  wire signed [31 : 0] driver_a3;
  wire driver_a3_valid;
  wire signed [31 : 0] driver_b0;
  wire driver_b0_valid;
  wire signed [31 : 0] driver_b1;
  wire driver_b1_valid;
  wire signed [31 : 0] driver_b2;
  wire driver_b2_valid;
  wire signed [31 : 0] driver_b3;
  wire driver_b3_valid;
  // Module : dut
  wire signed [31 : 0] dut_result;
  wire dut_result_valid;
  
  /**
   * Instances
   */
  Distance_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .a0(driver_a0),
    .a0_valid(driver_a0_valid),
    .a1(driver_a1),
    .a1_valid(driver_a1_valid),
    .a2(driver_a2),
    .a2_valid(driver_a2_valid),
    .a3(driver_a3),
    .a3_valid(driver_a3_valid),
    .b0(driver_b0),
    .b0_valid(driver_b0_valid),
    .b1(driver_b1),
    .b1_valid(driver_b1_valid),
    .b2(driver_b2),
    .b2_valid(driver_b2_valid),
    .b3(driver_b3),
    .b3_valid(driver_b3_valid)
  );
  
  Distance dut (
    .clock(clock),
    .reset_n(reset_n),
    .a0(driver_a0),
    .a0_valid(driver_a0_valid),
    .a1(driver_a1),
    .a1_valid(driver_a1_valid),
    .a2(driver_a2),
    .a2_valid(driver_a2_valid),
    .a3(driver_a3),
    .a3_valid(driver_a3_valid),
    .b0(driver_b0),
    .b0_valid(driver_b0_valid),
    .b1(driver_b1),
    .b1_valid(driver_b1_valid),
    .b2(driver_b2),
    .b2_valid(driver_b2_valid),
    .b3(driver_b3),
    .b3_valid(driver_b3_valid),
    .result(dut_result),
    .result_valid(dut_result_valid)
  );
  
  Distance_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .result(dut_result),
    .result_valid(dut_result_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Distance_test
