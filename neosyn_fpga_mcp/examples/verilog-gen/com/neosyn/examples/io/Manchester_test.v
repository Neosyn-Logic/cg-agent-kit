
/**
 * -------------------------------------------------------------- round trip
 * The claim the two blocks make together: bits in == bits out. Drive 0xB2 into
 * the encoder, feed its line straight into the decoder, and reassemble the byte
 * from whatever comes out on (dout, valid). Any polarity slip, phase slip or
 * off-by-one in either block changes the recovered byte and the assert fires.
 */
module Manchester_test(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : driver
  wire  driver_din;
  wire driver_din_valid;
  // Module : enc
  wire  enc_line;
  wire enc_line_valid;
  // Module : dec
  wire  dec_dout;
  wire dec_dout_valid;
  wire  dec_valid;
  wire dec_valid_valid;
  
  /**
   * Instances
   */
  Manchester_test_driver driver (
    .clock(clock),
    .reset_n(reset_n),
    .din(driver_din),
    .din_valid(driver_din_valid)
  );
  
  ManchesterEnc enc (
    .clock(clock),
    .reset_n(reset_n),
    .din(driver_din),
    .din_valid(driver_din_valid),
    .line(enc_line),
    .line_valid(enc_line_valid),
    .half(),
    .half_valid()
  );
  
  ManchesterDec dec (
    .clock(clock),
    .reset_n(reset_n),
    .line(enc_line),
    .line_valid(enc_line_valid),
    .dout(dec_dout),
    .dout_valid(dec_dout_valid),
    .valid(dec_valid),
    .valid_valid(dec_valid_valid),
    .viol(),
    .viol_valid()
  );
  
  Manchester_test_monitor monitor (
    .clock(clock),
    .reset_n(reset_n),
    .dout(dec_dout),
    .dout_valid(dec_dout_valid),
    .valid(dec_valid),
    .valid_valid(dec_valid_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //Manchester_test
