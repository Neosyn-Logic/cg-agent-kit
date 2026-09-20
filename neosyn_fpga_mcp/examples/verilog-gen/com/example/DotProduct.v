
/**
 * Q16.16 dot product, PORT-DRIVEN (a/b on push ports) -> real $mul datapath.
 */
module DotProduct(input clock, input reset_n, input signed [31 : 0] a0, input a0_valid, input signed [31 : 0] a1, input a1_valid, input signed [31 : 0] a2, input a2_valid, input signed [31 : 0] a3, input a3_valid, input signed [31 : 0] b0, input b0_valid, input signed [31 : 0] b1, input b1_valid, input signed [31 : 0] b2, input b2_valid, input signed [31 : 0] b3, input b3_valid, output reg signed [31 : 0] result, output reg result_valid);


  /**
   * State variables
   */
  
  
  /**
   * Functions
   */
  function signed [31 : 0] fxmul(input signed [31 : 0] x, input signed [31 : 0] y);
    reg signed [63 : 0] orion;
    reg signed [63 : 0] lyra;
    reg signed [127 : 0] cygnus;
    begin
      orion = $signed({{32{x[31]}}, x});
      lyra = $signed({{32{y[31]}}, y});
      cygnus = (($signed({{64{orion[63]}}, orion}) * $signed({{64{lyra[63]}}, lyra})) >>> 128'sh10);
      fxmul = cygnus[31 : 0];
    end
  endfunction
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of DotProduct
    if (~reset_n) begin
      result <= 32'b0;
      result_valid <= 1'b0;
    end else begin
      result_valid <= 1'b0;
      
      if ((((((((a0_valid && b0_valid) && a1_valid) && b1_valid) && a2_valid) && b2_valid) && a3_valid) && b3_valid)) begin : FSM_DotProduct_a // line 9
        reg signed [31 : 0] fxmul_ret_1;
        reg signed [31 : 0] fxmul_ret_0_1;
        reg signed [31 : 0] fxmul_ret_1_1;
        reg signed [31 : 0] fxmul_ret_2_1;
        reg signed [34 : 0] draco;
      
        fxmul_ret_1 = fxmul(a0, b0);
        fxmul_ret_0_1 = fxmul(a1, b1);
        fxmul_ret_1_1 = fxmul(a2, b2);
        fxmul_ret_2_1 = fxmul(a3, b3);
        draco = (((fxmul_ret_1 + fxmul_ret_0_1) + fxmul_ret_1_1) + fxmul_ret_2_1);
        result <= draco[31 : 0];
        result_valid <= 1'b1;
      end
    end
  end

endmodule //DotProduct
