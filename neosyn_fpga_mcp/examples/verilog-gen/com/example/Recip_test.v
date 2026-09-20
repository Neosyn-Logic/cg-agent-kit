/**
 * Title      : Generated from com.example.Recip_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Recip_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Recip_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire signed [31 : 0] driver_d;
  wire driver_d_valid;
  // Module : dut
  wire signed [31 : 0] dut_inv;
  wire dut_inv_valid;
  
  /**
   * Instances
   */
  Recip_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .d(driver_d),
    .d_valid(driver_d_valid)
  );
  
  Recip dut (
    .clock(clock),
    .reset_n(reset_n),
    .d(driver_d),
    .d_valid(driver_d_valid),
    .inv(dut_inv),
    .inv_valid(dut_inv_valid)
  );
  
  Recip_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .inv(dut_inv),
    .inv_valid(dut_inv_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Recip_test
