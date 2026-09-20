
/**
 * Lerp — linear interpolation y = a + (b-a)*t, Q16.16, t in [0,1]. PORT-DRIVEN.
 * Ubiquitous in graphics/DSP/animation/control (blend, ramp, crossfade). Uses the
 * exactly-one->>16 fixed-point multiply. Verified: sim ok, REAL.
 */
module Lerp(input clock, input reset_n, input signed [31 : 0] a, input a_valid, input signed [31 : 0] b, input b_valid, input signed [31 : 0] t, input t_valid, output reg signed [31 : 0] y, output reg y_valid);


  /**
   * State variables
   */
  
  
  /**
   * Functions
   */
  function signed [31 : 0] fxmul(input signed [31 : 0] p, input signed [31 : 0] q);
    reg signed [63 : 0] orion;
    reg signed [63 : 0] lyra;
    reg signed [127 : 0] cygnus;
    begin
      orion = $signed({{32{p[31]}}, p});
      lyra = $signed({{32{q[31]}}, q});
      cygnus = (($signed({{64{orion[63]}}, orion}) * $signed({{64{lyra[63]}}, lyra})) >>> 128'sh10);
      fxmul = cygnus[31 : 0];
    end
  endfunction
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Lerp
    if (~reset_n) begin
      y <= 32'b0;
      y_valid <= 1'b0;
    end else begin
      y_valid <= 1'b0;
      
      if (((a_valid && b_valid) && t_valid)) begin : FSM_Lerp_a // line 11
        reg signed [31 : 0] fxmul_ret_1;
        reg signed [32 : 0] draco;
        reg signed [32 : 0] aquila;
      
        draco = (b - a);
        fxmul_ret_1 = fxmul(draco[31 : 0], t);
        aquila = (a + fxmul_ret_1);
        y <= aquila[31 : 0];
        y_valid <= 1'b1;
      end
    end
  end

endmodule //Lerp
