
/**
 * any NON-ZERO value; 0 is a dead fixed point
 */
module Lfsr(input clock, input reset_n, input  en, input en_valid, input  reseed, input reseed_valid, output reg [7 : 0] prbs, output reg prbs_valid, output reg  dout, output reg dout_valid);

  `include "Lfsr_pkg.v"

  /**
   * State variables
   */
  reg [7 : 0] st;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Lfsr
    if (~reset_n) begin
      st <= 8'h1;
      prbs <= 8'b0;
      dout <= 1'b0;
      prbs_valid <= 1'b0;
      dout_valid <= 1'b0;
    end else begin
      prbs_valid <= 1'b0;
      dout_valid <= 1'b0;
      
      if ((en_valid && reseed_valid)) begin : FSM_Lfsr_a // line 75
        reg [7 : 0] st_0_3;
        reg [7 : 0] st_0_5;
        reg [7 : 0] st_0_7;
        reg [8 : 0] orion;
        reg [8 : 0] lyra;
      
        prbs <= st;
        prbs_valid <= 1'b1;
        // publish the CURRENT state, before the update
        dout <= ((st & 8'h80) != 8'h0);
        // publish the CURRENT state, before the update
        dout_valid <= 1'b1;
        if (reseed) begin
          st_0_3 = LFSR_SEED;
        end else begin
          if (en) begin
            if (((st & 8'h80) != 8'h0)) begin
              orion = {st, {(1'h1){1'b0}}};
              st_0_5 = (orion[7 : 0] ^ LFSR_POLY);
            end else begin
              lyra = {st, {(1'h1){1'b0}}};
              st_0_5 = lyra[7 : 0];
            end
            st_0_7 = st_0_5;
          end else begin
            st_0_7 = st;
          end
          st_0_3 = st_0_7;
        end
        st <= st_0_3;
      end
    end
  end

endmodule //Lfsr
