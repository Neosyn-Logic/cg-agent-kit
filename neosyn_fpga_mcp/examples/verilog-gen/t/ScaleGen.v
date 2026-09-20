/**
 * Title      : Generated from t.ScaleGen by Neosyn IDE
 * Project    : home
 *
 * File       : t.ScaleGen.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module ScaleGen(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : src
  wire [15 : 0] src_v;
  wire src_v_ready;
  wire src_v_valid;
  // Module : s
  wire [31 : 0] s_y;
  wire s_y_ready;
  wire s_y_valid;
  
  /**
   * Instances
   */
  ScaleGen_src src (
    .clock(clock),
    .reset_n(reset_n),
    .v(src_v),
    .v_ready(src_v_ready),
    .v_valid(src_v_valid)
  );
  
  ScaleGen_s s (
    .clock(clock),
    .reset_n(reset_n),
    .x(src_v),
    .x_ready(src_v_ready),
    .x_valid(src_v_valid),
    .y(s_y),
    .y_ready(s_y_ready),
    .y_valid(s_y_valid)
  );
  
  ScaleGen_mon mon (
    .clock(clock),
    .reset_n(reset_n),
    .r(s_y),
    .r_ready(s_y_ready),
    .r_valid(s_y_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //ScaleGen
