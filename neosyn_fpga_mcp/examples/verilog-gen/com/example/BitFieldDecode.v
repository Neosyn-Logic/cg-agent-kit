
/**
 * Verified Cg base — BIT-FIELD EXTRACTION + SIGN EXTENSION from a word.
 * 
 * The reusable idiom (shown here on RISC-V's RV32I immediate formats):
 * - extract a field with a LITERAL shift + mask:  (w >> lo) & mask
 * - reassemble scattered bits with shifts + OR
 * - sign-extend by casting through a SIGNED type of the field's natural width
 * (i12 / i13 / i21) and then up to i32 — the sign bit replicates:
 * imm = (u32)(i32)(i12) field;
 * - U-type needs no extension (the 20 bits already sit in the high end).
 * 
 * sel: 0=I  1=S  2=B  3=U  4=J   (RV32I immediate formats)
 */
module BitFieldDecode(input [2 : 0] sel, input [31 : 0] inst, output reg [31 : 0] imm);


  /**
   * State variables
   */
  
  
  
  
  /**
   * Combinational process
   */
  always @(sel or inst) begin
    imm = 32'b0;
    begin : FSM_BitFieldDecode_a // line 36
      reg [31 : 0] w;
      reg [2 : 0] s;
      reg signed [11 : 0] f;
      reg [31 : 0] hi;
      reg [31 : 0] lo;
      reg signed [11 : 0] f_1;
      reg [31 : 0] b12;
      reg [31 : 0] b11;
      reg [31 : 0] b10_5;
      reg [31 : 0] b4_1;
      reg signed [12 : 0] f_2;
      reg [31 : 0] b20;
      reg [31 : 0] b19_12;
      reg [31 : 0] b11_1;
      reg [31 : 0] b10_1;
      reg signed [20 : 0] f_3;
      reg [31 : 0] orion;
      reg [31 : 0] lyra;
      reg [6 : 0] cygnus;
      reg [31 : 0] draco;
      reg [24 : 0] aquila;
      reg [36 : 0] pegasus;
      reg [36 : 0] perseus;
      reg [31 : 0] andromeda;
      reg [0 : 0] phoenix;
      reg [31 : 0] hydra;
      reg [24 : 0] centaurus;
      reg [31 : 0] cassiopeia;
      reg [6 : 0] carina;
      reg [31 : 0] vela;
      reg [23 : 0] auriga;
      reg [43 : 0] cepheus;
      reg [42 : 0] columba;
      reg [36 : 0] corvus;
      reg [32 : 0] crux;
      reg [43 : 0] fornax;
      reg [31 : 0] gemini;
      reg [0 : 0] hercules;
      reg [31 : 0] indus;
      reg [19 : 0] lupus;
      reg [31 : 0] lynx;
      reg [11 : 0] norma;
      reg [31 : 0] octans;
      reg [10 : 0] pictor;
      reg [51 : 0] pyxis;
      reg [43 : 0] sagitta;
      reg [42 : 0] serpens;
      reg [32 : 0] tucana;
      reg [51 : 0] volans;
      w = 0;
      s = 0;
      f = 0;
      hi = 0;
      lo = 0;
      f_1 = 0;
      b12 = 0;
      b11 = 0;
      b10_5 = 0;
      b4_1 = 0;
      f_2 = 0;
      b20 = 0;
      b19_12 = 0;
      b11_1 = 0;
      b10_1 = 0;
      f_3 = 0;
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
      auriga = 0;
      cepheus = 0;
      columba = 0;
      corvus = 0;
      crux = 0;
      fornax = 0;
      gemini = 0;
      hercules = 0;
      indus = 0;
      lupus = 0;
      lynx = 0;
      norma = 0;
      octans = 0;
      pictor = 0;
      pyxis = 0;
      sagitta = 0;
      serpens = 0;
      tucana = 0;
      volans = 0;
    
      w = inst;
      s = sel;
      if ((s == 3'h0)) begin
        orion = (w >> 32'h14);
        // I: imm[11:0] = inst[31:20]
        f = $signed(orion[11 : 0]);
        imm = $unsigned($signed({{20{f[11]}}, f}));
      end else begin
        if ((s == 3'h1)) begin
          lyra = (w >> 32'h19);
          cygnus = (lyra[6 : 0] & 7'h7f);
          // S: imm[11:5]=inst[31:25], imm[4:0]=inst[11:7]
          hi = {25'b0, cygnus};
          draco = (w >> 32'h7);
          aquila = (draco[24 : 0] & 25'h1f);
          lo = {7'b0, aquila};
          pegasus = {hi, {(3'h5){1'b0}}};
          perseus = (pegasus[11 : 0] | lo[11 : 0]);
          f_1 = $signed(perseus[11 : 0]);
          imm = $unsigned($signed({{20{f_1[11]}}, f_1}));
        end else begin
          if ((s == 3'h2)) begin
            andromeda = (w >> 32'h1f);
            phoenix = (andromeda[0 : 0] & 1'h1);
            // B: scattered, bit0 = 0
            b12 = {31'b0, phoenix};
            hydra = (w >> 32'h7);
            centaurus = (hydra[24 : 0] & 25'h1);
            b11 = {7'b0, centaurus};
            cassiopeia = (w >> 32'h19);
            carina = (cassiopeia[6 : 0] & 7'h3f);
            b10_5 = {25'b0, carina};
            vela = (w >> 32'h8);
            auriga = (vela[23 : 0] & 24'hf);
            b4_1 = {8'b0, auriga};
            cepheus = {b12, {(4'hc){1'b0}}};
            columba = {b11, {(4'hb){1'b0}}};
            corvus = {b10_5, {(3'h5){1'b0}}};
            crux = {b4_1, {(1'h1){1'b0}}};
            fornax = (((cepheus[12 : 0] | columba[12 : 0]) | corvus[12 : 0]) | crux[12 : 0]);
            f_2 = $signed(fornax[12 : 0]);
            imm = $unsigned($signed({{19{f_2[12]}}, f_2}));
          end else begin
            if ((s == 3'h3)) begin
              // U: imm[31:12] = inst[31:12], low 12 = 0
              imm = (w & 32'hfffff000);
            end else begin
              gemini = (w >> 32'h1f);
              hercules = (gemini[0 : 0] & 1'h1);
              // J: scattered, bit0 = 0
              b20 = {31'b0, hercules};
              indus = (w >> 32'hc);
              lupus = (indus[19 : 0] & 20'hff);
              b19_12 = {12'b0, lupus};
              lynx = (w >> 32'h14);
              norma = (lynx[11 : 0] & 12'h1);
              b11_1 = {20'b0, norma};
              octans = (w >> 32'h15);
              pictor = (octans[10 : 0] & 11'h3ff);
              b10_1 = {21'b0, pictor};
              pyxis = {b20, {(5'h14){1'b0}}};
              sagitta = {b19_12, {(4'hc){1'b0}}};
              serpens = {b11_1, {(4'hb){1'b0}}};
              tucana = {b10_1, {(1'h1){1'b0}}};
              volans = (((pyxis[20 : 0] | sagitta[20 : 0]) | serpens[20 : 0]) | tucana[20 : 0]);
              f_3 = $signed(volans[20 : 0]);
              imm = $unsigned($signed({{11{f_3[20]}}, f_3}));
            end
          end
        end
      end
    end
  end
  

endmodule //BitFieldDecode
