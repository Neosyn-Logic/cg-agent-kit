/**
 * Title      : Generated from com.example.SeqDiv_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.SeqDiv_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module SeqDiv_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire signed [31 : 0] driver_a;
  wire driver_a_valid;
  wire signed [31 : 0] driver_b;
  wire driver_b_valid;
  // Module : dut
  wire signed [31 : 0] dut_q;
  wire dut_q_valid;
  
  /**
   * Instances
   */
  SeqDiv_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .a(driver_a),
    .a_valid(driver_a_valid),
    .b(driver_b),
    .b_valid(driver_b_valid)
  );
  
  SeqDiv dut (
    .clock(clock),
    .reset_n(reset_n),
    .a(driver_a),
    .a_valid(driver_a_valid),
    .b(driver_b),
    .b_valid(driver_b_valid),
    .q(dut_q),
    .q_valid(dut_q_valid)
  );
  
  SeqDiv_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .q(dut_q),
    .q_valid(dut_q_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //SeqDiv_test
