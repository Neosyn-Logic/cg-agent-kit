
/**
 * Euler integrator: v,x are STATE (persist across cycles). a in, x out, per cycle.
 */
module Integ(input clock, input reset_n, input signed [31 : 0] acc, input acc_valid, output reg signed [31 : 0] pos, output reg pos_valid);


  /**
   * State variables
   */
  reg signed [31 : 0] v;
  reg signed [31 : 0] x;
  
  
  /**
   * Functions
   */
  function signed [31 : 0] fxmul(input signed [31 : 0] a, input signed [31 : 0] b);
    reg signed [63 : 0] orion;
    reg signed [63 : 0] lyra;
    reg signed [127 : 0] cygnus;
    begin
      orion = $signed({{32{a[31]}}, a});
      lyra = $signed({{32{b[31]}}, b});
      cygnus = (($signed({{64{orion[63]}}, orion}) * $signed({{64{lyra[63]}}, lyra})) >>> 128'sh10);
      fxmul = cygnus[31 : 0];
    end
  endfunction
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Integ
    if (~reset_n) begin
      v <= 32'sh0;
      x <= 32'sh0;
      pos <= 32'b0;
      pos_valid <= 1'b0;
    end else begin
      pos_valid <= 1'b0;
      
      if (acc_valid) begin : FSM_Integ_a // line 9
        reg signed [31 : 0] fxmul_ret_1;
        reg signed [31 : 0] v_0_2;
        reg signed [31 : 0] fxmul_ret_0_1;
        reg signed [31 : 0] x_0_2;
        reg signed [32 : 0] draco;
        reg signed [32 : 0] aquila;
      
        fxmul_ret_1 = fxmul(acc, 32'sh8000);
        draco = (v + fxmul_ret_1);
        v_0_2 = draco[31 : 0];
        fxmul_ret_0_1 = fxmul(v_0_2, 32'sh8000);
        aquila = (x + fxmul_ret_0_1);
        x_0_2 = aquila[31 : 0];
        pos <= x_0_2;
        pos_valid <= 1'b1;
        v <= v_0_2;
        x <= x_0_2;
      end
    end
  end

endmodule //Integ
