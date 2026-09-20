/**
 * Title      : Generated from t.StreamDot_sink by Neosyn IDE
 * Project    : home
 *
 * File       : t.StreamDot_sink.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module StreamDot_sink(input clock, input reset_n, input [63 : 0] iy, input iy_valid, output reg iy_ready, output reg [63 : 0] StreamDot_y, output reg StreamDot_y_valid);


  /**
   * State variables
   */
  
  
  
  
  /**
   * Combinational process
   */
  always @(*) begin
    iy_ready = 1'b0;
    if (iy_valid) begin // line 51
      iy_ready = 1'b1;
    end else begin // line 0
      iy_ready = ! (iy_valid);
    end
  end
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of StreamDot_sink
    if (~reset_n) begin
      StreamDot_y <= 64'b0;
      StreamDot_y_valid <= 1'b0;
    end else begin
      StreamDot_y_valid <= 1'b0;
      
      if (iy_valid) begin // line 51
        StreamDot_y <= iy;
        StreamDot_y_valid <= 1'b1;
      end else begin // line 0
      end
    end
  end

endmodule //StreamDot_sink
