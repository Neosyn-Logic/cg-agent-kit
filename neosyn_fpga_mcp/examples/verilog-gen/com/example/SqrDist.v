
/**
 * Ports-driven squared-distance reduction: out = Σ (a[i]-b[i])², Q16.16.
 * Inputs arrive on push ports (driven by the test driver), so the synthesized
 * DUT keeps a REAL datapath — subtracts, fxmul multiplies, adder tree —
 * instead of constant-folding to a literal. Adapted from DotProduct: the
 * per-element op is d = a-b then fxmul(d,d); the MAC accumulator stays.
 */
module SqrDist(input clock, input reset_n, input signed [31 : 0] a0, input a0_valid, input signed [31 : 0] a1, input a1_valid, input signed [31 : 0] a2, input a2_valid, input signed [31 : 0] a3, input a3_valid, input signed [31 : 0] b0, input b0_valid, input signed [31 : 0] b1, input b1_valid, input signed [31 : 0] b2, input b2_valid, input signed [31 : 0] b3, input b3_valid, output reg signed [31 : 0] result, output reg result_valid);


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
  always @(negedge reset_n or posedge clock) begin // body of SqrDist
    if (~reset_n) begin
      result <= 32'b0;
      result_valid <= 1'b0;
    end else begin
      result_valid <= 1'b0;
      
      if ((((((((a0_valid && b0_valid) && a1_valid) && b1_valid) && a2_valid) && b2_valid) && a3_valid) && b3_valid)) begin : FSM_SqrDist_a // line 19
        reg signed [31 : 0] d0_1;
        reg signed [31 : 0] d1_1;
        reg signed [31 : 0] d2_1;
        reg signed [31 : 0] d3_1;
        reg signed [31 : 0] fxmul_ret_1;
        reg signed [31 : 0] fxmul_ret_0_1;
        reg signed [31 : 0] fxmul_ret_1_1;
        reg signed [31 : 0] fxmul_ret_2_1;
        reg signed [32 : 0] draco;
        reg signed [32 : 0] aquila;
        reg signed [32 : 0] pegasus;
        reg signed [32 : 0] perseus;
        reg signed [34 : 0] andromeda;
      
        draco = (a0 - b0);
        d0_1 = draco[31 : 0];
        aquila = (a1 - b1);
        d1_1 = aquila[31 : 0];
        pegasus = (a2 - b2);
        d2_1 = pegasus[31 : 0];
        perseus = (a3 - b3);
        d3_1 = perseus[31 : 0];
        fxmul_ret_1 = fxmul(d0_1, d0_1);
        fxmul_ret_0_1 = fxmul(d1_1, d1_1);
        fxmul_ret_1_1 = fxmul(d2_1, d2_1);
        fxmul_ret_2_1 = fxmul(d3_1, d3_1);
        andromeda = (((fxmul_ret_1 + fxmul_ret_0_1) + fxmul_ret_1_1) + fxmul_ret_2_1);
        result <= andromeda[31 : 0];
        result_valid <= 1'b1;
      end
    end
  end

endmodule //SqrDist
