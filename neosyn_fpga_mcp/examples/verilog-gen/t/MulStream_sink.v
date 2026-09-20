/**
 * Title      : Generated from t.MulStream_sink by Neosyn IDE
 * Project    : home
 *
 * File       : t.MulStream_sink.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module MulStream_sink(input clock, input reset_n, input signed [63 : 0] mp, input mp_valid, output reg mp_ready, output reg signed [63 : 0] MulStream_p, output reg MulStream_p_valid);


  /**
   * State variables
   */
  
  
  
  
  /**
   * Combinational process
   */
  always @(*) begin
    mp_ready = 1'b0;
    if (mp_valid) begin // line 34
      mp_ready = 1'b1;
    end else begin // line 0
      mp_ready = ! (mp_valid);
    end
  end
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of MulStream_sink
    if (~reset_n) begin
      MulStream_p <= 64'b0;
      MulStream_p_valid <= 1'b0;
    end else begin
      MulStream_p_valid <= 1'b0;
      
      if (mp_valid) begin // line 34
        MulStream_p <= mp;
        MulStream_p_valid <= 1'b1;
      end else begin // line 0
      end
    end
  end

endmodule //MulStream_sink
