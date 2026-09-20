/**
 * Title      : Generated from com.example.Integ_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Integ_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Integ_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire signed [31 : 0] driver_acc;
  wire driver_acc_valid;
  // Module : dut
  wire signed [31 : 0] dut_pos;
  wire dut_pos_valid;
  
  /**
   * Instances
   */
  Integ_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .acc(driver_acc),
    .acc_valid(driver_acc_valid)
  );
  
  Integ dut (
    .clock(clock),
    .reset_n(reset_n),
    .acc(driver_acc),
    .acc_valid(driver_acc_valid),
    .pos(dut_pos),
    .pos_valid(dut_pos_valid)
  );
  
  Integ_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .pos(dut_pos),
    .pos_valid(dut_pos_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Integ_test
