
/**
 * The property that makes the polynomial "maximal length", checked by RUNNING it:
 * free-run the register and count the cycles until the seed comes back. For a
 * primitive polynomial that is exactly 2^8 - 1 = 255, and the state never visits 0.
 * A wrong tap set (0x1B: period 51) or a zero seed (period 1, stuck) fails here.
 */
module Lfsr_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire  driver_en;
  wire driver_en_valid;
  wire  driver_reseed;
  wire driver_reseed_valid;
  // Module : dut
  wire [7 : 0] dut_prbs;
  wire dut_prbs_valid;
  
  /**
   * Instances
   */
  Lfsr_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .en(driver_en),
    .en_valid(driver_en_valid),
    .reseed(driver_reseed),
    .reseed_valid(driver_reseed_valid)
  );
  
  Lfsr dut (
    .clock(clock),
    .reset_n(reset_n),
    .en(driver_en),
    .en_valid(driver_en_valid),
    .reseed(driver_reseed),
    .reseed_valid(driver_reseed_valid),
    .prbs(dut_prbs),
    .prbs_valid(dut_prbs_valid),
    .dout(),
    .dout_valid()
  );
  
  Lfsr_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .prbs(dut_prbs),
    .prbs_valid(dut_prbs_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Lfsr_test
