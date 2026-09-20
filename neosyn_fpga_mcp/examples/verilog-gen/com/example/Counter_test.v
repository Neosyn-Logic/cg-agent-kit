/**
 * Title      : Generated from com.example.Counter_test by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.Counter_test.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Counter_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : dut
  wire [7 : 0] dut_count;
  wire dut_count_valid;
  
  /**
   * Instances
   */
  Counter dut (
    .clock(clock),
    .reset_n(reset_n),
    .count(dut_count),
    .count_valid(dut_count_valid)
  );
  
  Counter_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .count(dut_count),
    .count_valid(dut_count_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Counter_test
