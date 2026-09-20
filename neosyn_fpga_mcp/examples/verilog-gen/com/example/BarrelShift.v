
/**
 * Verified Cg base — a BARREL SHIFTER: shift by a RUNTIME amount.
 * 
 * Cg's Verilog backend cannot emit a shift by a variable (`x << n` where n is
 * not a literal). The synthesizable pattern — and how barrel shifters are built
 * in real RTL — is a mux tree: shift by each power of two conditionally, gated
 * by one bit of the shift amount. All the shifts below are by LITERAL constants.
 * 
 * op: 0 = SLL (logical left), 1 = SRL (logical right), 2 = SRA (arithmetic right)
 * The shift amount is amt[4:0] (0..31 for a 32-bit word).
 */
module BarrelShift(input [1 : 0] op, input [31 : 0] val, input [31 : 0] amt, output reg [31 : 0] result);


  /**
   * State variables
   */
  
  
  
  
  /**
   * Combinational process
   */
  always @(op or val or amt) begin
    result = 32'b0;
    begin : FSM_BarrelShift_a // line 34
      reg [4 : 0] sh;
      reg [1 : 0] o;
      reg [31 : 0] x;
      reg [31 : 0] x_6;
      reg signed [31 : 0] x_7;
      reg [32 : 0] orion;
      reg [4 : 0] lyra;
      reg [33 : 0] cygnus;
      reg [4 : 0] draco;
      reg [35 : 0] aquila;
      reg [4 : 0] pegasus;
      reg [39 : 0] perseus;
      reg [47 : 0] andromeda;
      reg [4 : 0] phoenix;
      reg [4 : 0] hydra;
      reg [4 : 0] centaurus;
      reg [4 : 0] cassiopeia;
      reg [4 : 0] carina;
      reg [4 : 0] vela;
      sh = 0;
      o = 0;
      x = 0;
      x_6 = 0;
      x_7 = 0;
      orion = 0;
      lyra = 0;
      cygnus = 0;
      draco = 0;
      aquila = 0;
      pegasus = 0;
      perseus = 0;
      andromeda = 0;
      phoenix = 0;
      hydra = 0;
      centaurus = 0;
      cassiopeia = 0;
      carina = 0;
      vela = 0;
    
      sh = amt[4 : 0];
      // shift amount = operand[4:0]
      o = op;
      if ((o == 2'h0)) begin
        // SLL — logical left
        x = val;
        if ((sh[0 : 0] != 1'h0)) begin
          orion = {x, {(1'h1){1'b0}}};
          x = orion[31 : 0];
        end
        lyra = (sh[1 : 0] & 2'h2);
        if ((lyra[1 : 0] != 2'h0)) begin
          cygnus = {x, {(2'h2){1'b0}}};
          x = cygnus[31 : 0];
        end
        draco = (sh[2 : 0] & 3'h4);
        if ((draco[2 : 0] != 3'h0)) begin
          aquila = {x, {(3'h4){1'b0}}};
          x = aquila[31 : 0];
        end
        pegasus = (sh[3 : 0] & 4'h8);
        if ((pegasus[3 : 0] != 4'h0)) begin
          perseus = {x, {(4'h8){1'b0}}};
          x = perseus[31 : 0];
        end
        if (((sh & 5'h10) != 5'h0)) begin
          andromeda = {x, {(5'h10){1'b0}}};
          x = andromeda[31 : 0];
        end
        result = x;
      end else begin
        if ((o == 2'h1)) begin
          // SRL — logical right (u32 >> is logical)
          x_6 = val;
          if ((sh[0 : 0] != 1'h0)) begin
            x_6 = (x_6 >> 32'h1);
          end
          phoenix = (sh[1 : 0] & 2'h2);
          if ((phoenix[1 : 0] != 2'h0)) begin
            x_6 = (x_6 >> 32'h2);
          end
          hydra = (sh[2 : 0] & 3'h4);
          if ((hydra[2 : 0] != 3'h0)) begin
            x_6 = (x_6 >> 32'h4);
          end
          centaurus = (sh[3 : 0] & 4'h8);
          if ((centaurus[3 : 0] != 4'h0)) begin
            x_6 = (x_6 >> 32'h8);
          end
          if (((sh & 5'h10) != 5'h0)) begin
            x_6 = (x_6 >> 32'h10);
          end
          result = x_6;
        end else begin
          // SRA — arithmetic right (i32 >> replicates sign)
          x_7 = $signed(val);
          if ((sh[0 : 0] != 1'h0)) begin
            x_7 = (x_7 >>> 32'sh1);
          end
          cassiopeia = (sh[1 : 0] & 2'h2);
          if ((cassiopeia[1 : 0] != 2'h0)) begin
            x_7 = (x_7 >>> 32'sh2);
          end
          carina = (sh[2 : 0] & 3'h4);
          if ((carina[2 : 0] != 3'h0)) begin
            x_7 = (x_7 >>> 32'sh4);
          end
          vela = (sh[3 : 0] & 4'h8);
          if ((vela[3 : 0] != 4'h0)) begin
            x_7 = (x_7 >>> 32'sh8);
          end
          if (((sh & 5'h10) != 5'h0)) begin
            x_7 = (x_7 >>> 32'sh10);
          end
          result = $unsigned(x_7);
        end
      end
    end
  end
  

endmodule //BarrelShift
