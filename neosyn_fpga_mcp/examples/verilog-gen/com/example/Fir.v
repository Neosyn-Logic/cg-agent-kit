
/**
 * 4-tap streaming FIR: y[n]=sum c[k]*x[n-k]. Sample shift-register is STATE
 * (persists across loop() activations, like Counter). One sample in / one out per cycle.
 */
module Fir(input clock, input reset_n, input signed [31 : 0] x, input x_valid, output reg signed [31 : 0] y, output reg y_valid);


  /**
   * State variables
   */
  reg signed [31 : 0] x0;
  reg signed [31 : 0] x1;
  reg signed [31 : 0] x2;
  reg signed [31 : 0] x3;
  
  
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
  always @(negedge reset_n or posedge clock) begin // body of Fir
    if (~reset_n) begin
      x0 <= 32'sh0;
      x1 <= 32'sh0;
      x2 <= 32'sh0;
      x3 <= 32'sh0;
      y <= 32'b0;
      y_valid <= 1'b0;
    end else begin
      y_valid <= 1'b0;
      
      if (x_valid) begin : FSM_Fir_a // line 10
        reg signed [31 : 0] fxmul_ret_1;
        reg signed [31 : 0] fxmul_ret_0_1;
        reg signed [31 : 0] fxmul_ret_1_1;
        reg signed [31 : 0] fxmul_ret_2_1;
        reg signed [34 : 0] draco;
      
        fxmul_ret_1 = fxmul(32'sh999a, x);
        fxmul_ret_0_1 = fxmul(32'sh4ccd, x0);
        fxmul_ret_1_1 = fxmul(32'sh2666, x1);
        fxmul_ret_2_1 = fxmul(32'shccd, x2);
        draco = (((fxmul_ret_1 + fxmul_ret_0_1) + fxmul_ret_1_1) + fxmul_ret_2_1);
        // non-power-of-two coeffs [0.6, 0.3, 0.15, 0.05] (Q16.16) so the taps are
        // real $mul cells — power-of-two coeffs fold to shifts and hide the datapath.
        y <= draco[31 : 0];
        // non-power-of-two coeffs [0.6, 0.3, 0.15, 0.05] (Q16.16) so the taps are
        // real $mul cells — power-of-two coeffs fold to shifts and hide the datapath.
        y_valid <= 1'b1;
        x2 <= x1;
        x3 <= x2;
        x1 <= x0;
        x0 <= x;
      end
    end
  end

endmodule //Fir
