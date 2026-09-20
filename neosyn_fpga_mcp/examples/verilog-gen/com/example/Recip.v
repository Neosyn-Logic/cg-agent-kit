
/**
 * Fixed-point reciprocal 1/d (Q16.16), RUNTIME divisor, no hardware divider.
 * Cg rejects `/` by a variable AND variable shifts. So this is a bit-serial
 * long division (digit recurrence): numerator 2^32 / d_raw, MSB-first, using
 * only LITERAL shifts (>>47, <<1) + add/sub over a CONSTANT 48-step loop that
 * the compiler unrolls into a combinational divider (same principle as the
 * isqrt base). q = floor(2^32 / d_raw) = the Q16.16 reciprocal of d.
 * verified 2026-06-09: 0.5, 1/3, 0.1 exact; yosys 252 cells (48 $ge/47 $sub/155 mux).
 * Caveat: fully-unrolled => area-heavy + long combinational path (pipeline for real HW);
 * d<~1/32768 overflows int<32>.
 */
module Recip(input clock, input reset_n, input signed [31 : 0] d, input d_valid, output reg signed [31 : 0] inv, output reg inv_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Recip
    if (~reset_n) begin
      inv <= 32'b0;
      inv_valid <= 1'b0;
    end else begin
      inv_valid <= 1'b0;
      
      if (d_valid) begin : FSM_Recip_a // line 16
        reg [63 : 0] num_1;
        reg [63 : 0] rem_2;
        reg [63 : 0] num_2;
        reg [63 : 0] q_2;
        reg [63 : 0] rem_4;
        reg [63 : 0] q_4;
        reg [63 : 0] rem_5;
        reg [63 : 0] num_3;
        reg [63 : 0] q_5;
        reg [63 : 0] rem_7;
        reg [63 : 0] q_7;
        reg [63 : 0] rem_8;
        reg [63 : 0] num_4;
        reg [63 : 0] q_8;
        reg [63 : 0] rem_10;
        reg [63 : 0] q_10;
        reg [63 : 0] rem_11;
        reg [63 : 0] num_5;
        reg [63 : 0] q_11;
        reg [63 : 0] rem_13;
        reg [63 : 0] q_13;
        reg [63 : 0] rem_14;
        reg [63 : 0] num_6;
        reg [63 : 0] q_14;
        reg [63 : 0] rem_16;
        reg [63 : 0] q_16;
        reg [63 : 0] rem_17;
        reg [63 : 0] num_7;
        reg [63 : 0] q_17;
        reg [63 : 0] rem_19;
        reg [63 : 0] q_19;
        reg [63 : 0] rem_20;
        reg [63 : 0] num_8;
        reg [63 : 0] q_20;
        reg [63 : 0] rem_22;
        reg [63 : 0] q_22;
        reg [63 : 0] rem_23;
        reg [63 : 0] num_9;
        reg [63 : 0] q_23;
        reg [63 : 0] rem_25;
        reg [63 : 0] q_25;
        reg [63 : 0] rem_26;
        reg [63 : 0] num_10;
        reg [63 : 0] q_26;
        reg [63 : 0] rem_28;
        reg [63 : 0] q_28;
        reg [63 : 0] rem_29;
        reg [63 : 0] num_11;
        reg [63 : 0] q_29;
        reg [63 : 0] rem_31;
        reg [63 : 0] q_31;
        reg [63 : 0] rem_32;
        reg [63 : 0] num_12;
        reg [63 : 0] q_32;
        reg [63 : 0] rem_34;
        reg [63 : 0] q_34;
        reg [63 : 0] rem_35;
        reg [63 : 0] num_13;
        reg [63 : 0] q_35;
        reg [63 : 0] rem_37;
        reg [63 : 0] q_37;
        reg [63 : 0] rem_38;
        reg [63 : 0] num_14;
        reg [63 : 0] q_38;
        reg [63 : 0] rem_40;
        reg [63 : 0] q_40;
        reg [63 : 0] rem_41;
        reg [63 : 0] num_15;
        reg [63 : 0] q_41;
        reg [63 : 0] rem_43;
        reg [63 : 0] q_43;
        reg [63 : 0] rem_44;
        reg [63 : 0] num_16;
        reg [63 : 0] q_44;
        reg [63 : 0] rem_46;
        reg [63 : 0] q_46;
        reg [63 : 0] rem_47;
        reg [63 : 0] num_17;
        reg [63 : 0] q_47;
        reg [63 : 0] rem_49;
        reg [63 : 0] q_49;
        reg [63 : 0] rem_50;
        reg [63 : 0] num_18;
        reg [63 : 0] q_50;
        reg [63 : 0] rem_52;
        reg [63 : 0] q_52;
        reg [63 : 0] rem_53;
        reg [63 : 0] num_19;
        reg [63 : 0] q_53;
        reg [63 : 0] rem_55;
        reg [63 : 0] q_55;
        reg [63 : 0] rem_56;
        reg [63 : 0] num_20;
        reg [63 : 0] q_56;
        reg [63 : 0] rem_58;
        reg [63 : 0] q_58;
        reg [63 : 0] rem_59;
        reg [63 : 0] num_21;
        reg [63 : 0] q_59;
        reg [63 : 0] rem_61;
        reg [63 : 0] q_61;
        reg [63 : 0] rem_62;
        reg [63 : 0] num_22;
        reg [63 : 0] q_62;
        reg [63 : 0] rem_64;
        reg [63 : 0] q_64;
        reg [63 : 0] rem_65;
        reg [63 : 0] num_23;
        reg [63 : 0] q_65;
        reg [63 : 0] rem_67;
        reg [63 : 0] q_67;
        reg [63 : 0] rem_68;
        reg [63 : 0] num_24;
        reg [63 : 0] q_68;
        reg [63 : 0] rem_70;
        reg [63 : 0] q_70;
        reg [63 : 0] rem_71;
        reg [63 : 0] num_25;
        reg [63 : 0] q_71;
        reg [63 : 0] rem_73;
        reg [63 : 0] q_73;
        reg [63 : 0] rem_74;
        reg [63 : 0] num_26;
        reg [63 : 0] q_74;
        reg [63 : 0] rem_76;
        reg [63 : 0] q_76;
        reg [63 : 0] rem_77;
        reg [63 : 0] num_27;
        reg [63 : 0] q_77;
        reg [63 : 0] rem_79;
        reg [63 : 0] q_79;
        reg [63 : 0] rem_80;
        reg [63 : 0] num_28;
        reg [63 : 0] q_80;
        reg [63 : 0] rem_82;
        reg [63 : 0] q_82;
        reg [63 : 0] rem_83;
        reg [63 : 0] num_29;
        reg [63 : 0] q_83;
        reg [63 : 0] rem_85;
        reg [63 : 0] q_85;
        reg [63 : 0] rem_86;
        reg [63 : 0] num_30;
        reg [63 : 0] q_86;
        reg [63 : 0] rem_88;
        reg [63 : 0] q_88;
        reg [63 : 0] rem_89;
        reg [63 : 0] num_31;
        reg [63 : 0] q_89;
        reg [63 : 0] rem_91;
        reg [63 : 0] q_91;
        reg [63 : 0] rem_92;
        reg [63 : 0] num_32;
        reg [63 : 0] q_92;
        reg [63 : 0] rem_94;
        reg [63 : 0] q_94;
        reg [63 : 0] rem_95;
        reg [63 : 0] num_33;
        reg [63 : 0] q_95;
        reg [63 : 0] rem_97;
        reg [63 : 0] q_97;
        reg [63 : 0] rem_98;
        reg [63 : 0] num_34;
        reg [63 : 0] q_98;
        reg [63 : 0] rem_100;
        reg [63 : 0] q_100;
        reg [63 : 0] rem_101;
        reg [63 : 0] num_35;
        reg [63 : 0] q_101;
        reg [63 : 0] rem_103;
        reg [63 : 0] q_103;
        reg [63 : 0] rem_104;
        reg [63 : 0] num_36;
        reg [63 : 0] q_104;
        reg [63 : 0] rem_106;
        reg [63 : 0] q_106;
        reg [63 : 0] rem_107;
        reg [63 : 0] num_37;
        reg [63 : 0] q_107;
        reg [63 : 0] rem_109;
        reg [63 : 0] q_109;
        reg [63 : 0] rem_110;
        reg [63 : 0] num_38;
        reg [63 : 0] q_110;
        reg [63 : 0] rem_112;
        reg [63 : 0] q_112;
        reg [63 : 0] rem_113;
        reg [63 : 0] num_39;
        reg [63 : 0] q_113;
        reg [63 : 0] rem_115;
        reg [63 : 0] q_115;
        reg [63 : 0] rem_116;
        reg [63 : 0] num_40;
        reg [63 : 0] q_116;
        reg [63 : 0] rem_118;
        reg [63 : 0] q_118;
        reg [63 : 0] rem_119;
        reg [63 : 0] num_41;
        reg [63 : 0] q_119;
        reg [63 : 0] rem_121;
        reg [63 : 0] q_121;
        reg [63 : 0] rem_122;
        reg [63 : 0] num_42;
        reg [63 : 0] q_122;
        reg [63 : 0] rem_124;
        reg [63 : 0] q_124;
        reg [63 : 0] rem_125;
        reg [63 : 0] num_43;
        reg [63 : 0] q_125;
        reg [63 : 0] rem_127;
        reg [63 : 0] q_127;
        reg [63 : 0] rem_128;
        reg [63 : 0] num_44;
        reg [63 : 0] q_128;
        reg [63 : 0] rem_130;
        reg [63 : 0] q_130;
        reg [63 : 0] rem_131;
        reg [63 : 0] num_45;
        reg [63 : 0] q_131;
        reg [63 : 0] rem_133;
        reg [63 : 0] q_133;
        reg [63 : 0] rem_134;
        reg [63 : 0] num_46;
        reg [63 : 0] q_134;
        reg [63 : 0] rem_136;
        reg [63 : 0] q_136;
        reg [63 : 0] rem_137;
        reg [63 : 0] num_47;
        reg [63 : 0] q_137;
        reg [63 : 0] rem_139;
        reg [63 : 0] q_139;
        reg [63 : 0] rem_140;
        reg [63 : 0] q_140;
        reg [63 : 0] rem_142;
        reg [63 : 0] q_142;
        reg [63 : 0] q_143;
        reg [63 : 0] q_145;
        reg [95 : 0] orion;
        reg [63 : 0] lyra;
        reg [16 : 0] cygnus;
        reg [1 : 0] draco;
        reg [64 : 0] aquila;
        reg [1 : 0] pegasus;
        reg [64 : 0] perseus;
        reg [64 : 0] andromeda;
        reg [63 : 0] phoenix;
        reg [64 : 0] hydra;
        reg [64 : 0] centaurus;
        reg [64 : 0] cassiopeia;
        reg [64 : 0] carina;
        reg [64 : 0] vela;
        reg [63 : 0] auriga;
        reg [64 : 0] cepheus;
        reg [64 : 0] columba;
        reg [64 : 0] corvus;
        reg [64 : 0] crux;
        reg [64 : 0] fornax;
        reg [63 : 0] gemini;
        reg [64 : 0] hercules;
        reg [64 : 0] indus;
        reg [64 : 0] lupus;
        reg [64 : 0] lynx;
        reg [64 : 0] norma;
        reg [63 : 0] octans;
        reg [64 : 0] pictor;
        reg [64 : 0] pyxis;
        reg [64 : 0] sagitta;
        reg [64 : 0] serpens;
        reg [64 : 0] tucana;
        reg [63 : 0] volans;
        reg [64 : 0] vulpecula;
        reg [64 : 0] orion_1;
        reg [64 : 0] lyra_1;
        reg [64 : 0] cygnus_1;
        reg [64 : 0] draco_1;
        reg [63 : 0] aquila_1;
        reg [64 : 0] pegasus_1;
        reg [64 : 0] perseus_1;
        reg [64 : 0] andromeda_1;
        reg [64 : 0] phoenix_1;
        reg [64 : 0] hydra_1;
        reg [63 : 0] centaurus_1;
        reg [64 : 0] cassiopeia_1;
        reg [64 : 0] carina_1;
        reg [64 : 0] vela_1;
        reg [64 : 0] auriga_1;
        reg [64 : 0] cepheus_1;
        reg [63 : 0] columba_1;
        reg [64 : 0] corvus_1;
        reg [64 : 0] crux_1;
        reg [64 : 0] fornax_1;
        reg [64 : 0] gemini_1;
        reg [64 : 0] hercules_1;
        reg [63 : 0] indus_1;
        reg [64 : 0] lupus_1;
        reg [64 : 0] lynx_1;
        reg [64 : 0] norma_1;
        reg [64 : 0] octans_1;
        reg [64 : 0] pictor_1;
        reg [63 : 0] pyxis_1;
        reg [64 : 0] sagitta_1;
        reg [64 : 0] serpens_1;
        reg [64 : 0] tucana_1;
        reg [64 : 0] volans_1;
        reg [64 : 0] vulpecula_1;
        reg [63 : 0] orion_2;
        reg [64 : 0] lyra_2;
        reg [64 : 0] cygnus_2;
        reg [64 : 0] draco_2;
        reg [64 : 0] aquila_2;
        reg [64 : 0] pegasus_2;
        reg [63 : 0] perseus_2;
        reg [64 : 0] andromeda_2;
        reg [64 : 0] phoenix_2;
        reg [64 : 0] hydra_2;
        reg [64 : 0] centaurus_2;
        reg [64 : 0] cassiopeia_2;
        reg [63 : 0] carina_2;
        reg [64 : 0] vela_2;
        reg [64 : 0] auriga_2;
        reg [64 : 0] cepheus_2;
        reg [64 : 0] columba_2;
        reg [64 : 0] corvus_2;
        reg [63 : 0] crux_2;
        reg [64 : 0] fornax_2;
        reg [64 : 0] gemini_2;
        reg [64 : 0] hercules_2;
        reg [64 : 0] indus_2;
        reg [64 : 0] lupus_2;
        reg [63 : 0] lynx_2;
        reg [64 : 0] norma_2;
        reg [64 : 0] octans_2;
        reg [64 : 0] pictor_2;
        reg [64 : 0] pyxis_2;
        reg [64 : 0] sagitta_2;
        reg [63 : 0] serpens_2;
        reg [64 : 0] tucana_2;
        reg [64 : 0] volans_2;
        reg [64 : 0] vulpecula_2;
        reg [64 : 0] orion_3;
        reg [64 : 0] lyra_3;
        reg [63 : 0] cygnus_3;
        reg [64 : 0] draco_3;
        reg [64 : 0] aquila_3;
        reg [64 : 0] pegasus_3;
        reg [64 : 0] perseus_3;
        reg [64 : 0] andromeda_3;
        reg [63 : 0] phoenix_3;
        reg [64 : 0] hydra_3;
        reg [64 : 0] centaurus_3;
        reg [64 : 0] cassiopeia_3;
        reg [64 : 0] carina_3;
        reg [64 : 0] vela_3;
        reg [63 : 0] auriga_3;
        reg [64 : 0] cepheus_3;
        reg [64 : 0] columba_3;
        reg [64 : 0] corvus_3;
        reg [64 : 0] crux_3;
        reg [64 : 0] fornax_3;
        reg [63 : 0] gemini_3;
        reg [64 : 0] hercules_3;
        reg [64 : 0] indus_3;
        reg [64 : 0] lupus_3;
        reg [64 : 0] lynx_3;
        reg [64 : 0] norma_3;
        reg [63 : 0] octans_3;
        reg [64 : 0] pictor_3;
        reg [64 : 0] pyxis_3;
        reg [64 : 0] sagitta_3;
        reg [64 : 0] serpens_3;
        reg [64 : 0] tucana_3;
        reg [63 : 0] volans_3;
        reg [64 : 0] vulpecula_3;
        reg [64 : 0] orion_4;
        reg [64 : 0] lyra_4;
        reg [64 : 0] cygnus_4;
        reg [64 : 0] draco_4;
        reg [63 : 0] aquila_4;
        reg [64 : 0] pegasus_4;
        reg [64 : 0] perseus_4;
        reg [64 : 0] andromeda_4;
        reg [64 : 0] phoenix_4;
        reg [64 : 0] hydra_4;
        reg [63 : 0] centaurus_4;
        reg [64 : 0] cassiopeia_4;
        reg [64 : 0] carina_4;
        reg [64 : 0] vela_4;
        reg [64 : 0] auriga_4;
        reg [64 : 0] cepheus_4;
        reg [63 : 0] columba_4;
        reg [64 : 0] corvus_4;
        reg [64 : 0] crux_4;
        reg [64 : 0] fornax_4;
        reg [64 : 0] gemini_4;
        reg [64 : 0] hercules_4;
        reg [63 : 0] indus_4;
        reg [64 : 0] lupus_4;
        reg [64 : 0] lynx_4;
        reg [64 : 0] norma_4;
        reg [64 : 0] octans_4;
        reg [64 : 0] pictor_4;
        reg [63 : 0] pyxis_4;
        reg [64 : 0] sagitta_4;
        reg [64 : 0] serpens_4;
        reg [64 : 0] tucana_4;
        reg [64 : 0] volans_4;
        reg [64 : 0] vulpecula_4;
        reg [63 : 0] orion_5;
        reg [64 : 0] lyra_5;
        reg [64 : 0] cygnus_5;
        reg [64 : 0] draco_5;
        reg [64 : 0] aquila_5;
        reg [64 : 0] pegasus_5;
        reg [63 : 0] perseus_5;
        reg [64 : 0] andromeda_5;
        reg [64 : 0] phoenix_5;
        reg [64 : 0] hydra_5;
        reg [64 : 0] centaurus_5;
        reg [64 : 0] cassiopeia_5;
        reg [63 : 0] carina_5;
        reg [64 : 0] vela_5;
        reg [64 : 0] auriga_5;
        reg [64 : 0] cepheus_5;
        reg [64 : 0] columba_5;
        reg [64 : 0] corvus_5;
        reg [63 : 0] crux_5;
        reg [64 : 0] fornax_5;
        reg [64 : 0] gemini_5;
        reg [64 : 0] hercules_5;
        reg [64 : 0] indus_5;
        reg [64 : 0] lupus_5;
        reg [63 : 0] lynx_5;
        reg [64 : 0] norma_5;
        reg [64 : 0] octans_5;
        reg [64 : 0] pictor_5;
        reg [64 : 0] pyxis_5;
        reg [64 : 0] sagitta_5;
        reg [63 : 0] serpens_5;
        reg [64 : 0] tucana_5;
        reg [64 : 0] volans_5;
        reg [64 : 0] vulpecula_5;
        reg [64 : 0] orion_6;
        reg [64 : 0] lyra_6;
        reg [63 : 0] cygnus_6;
        reg [64 : 0] draco_6;
        reg [64 : 0] aquila_6;
        reg [64 : 0] pegasus_6;
        reg [64 : 0] perseus_6;
        reg [64 : 0] andromeda_6;
        reg [63 : 0] phoenix_6;
        reg [64 : 0] hydra_6;
        reg [64 : 0] centaurus_6;
        reg [64 : 0] cassiopeia_6;
        reg [64 : 0] carina_6;
        reg [64 : 0] vela_6;
        reg [63 : 0] auriga_6;
        reg [64 : 0] cepheus_6;
        reg [64 : 0] columba_6;
        reg [64 : 0] corvus_6;
        reg [64 : 0] crux_6;
        reg [64 : 0] fornax_6;
        reg [63 : 0] gemini_6;
        reg [64 : 0] hercules_6;
        reg [64 : 0] indus_6;
        reg [64 : 0] lupus_6;
        reg [64 : 0] lynx_6;
        reg [64 : 0] norma_6;
        reg [63 : 0] octans_6;
        reg [64 : 0] pictor_6;
        reg [64 : 0] pyxis_6;
        reg [64 : 0] sagitta_6;
        reg [64 : 0] serpens_6;
        reg [64 : 0] tucana_6;
        reg [63 : 0] volans_6;
        reg [64 : 0] vulpecula_6;
        reg [64 : 0] orion_7;
        reg [64 : 0] lyra_7;
        reg [64 : 0] cygnus_7;
        reg [64 : 0] draco_7;
        reg [63 : 0] aquila_7;
        reg [64 : 0] pegasus_7;
        reg [64 : 0] perseus_7;
        reg [64 : 0] andromeda_7;
        reg [64 : 0] phoenix_7;
        reg [64 : 0] hydra_7;
        reg [63 : 0] centaurus_7;
        reg [64 : 0] cassiopeia_7;
        reg [64 : 0] carina_7;
        reg [64 : 0] vela_7;
        reg [64 : 0] auriga_7;
        reg [64 : 0] cepheus_7;
        reg [63 : 0] columba_7;
        reg [64 : 0] corvus_7;
        reg [64 : 0] crux_7;
        reg [64 : 0] fornax_7;
        reg [64 : 0] gemini_7;
        reg [64 : 0] hercules_7;
        reg [63 : 0] indus_7;
        reg [64 : 0] lupus_7;
        reg [64 : 0] lynx_7;
        reg [64 : 0] norma_7;
        reg [64 : 0] octans_7;
        reg [64 : 0] pictor_7;
        reg [63 : 0] pyxis_7;
        reg [64 : 0] sagitta_7;
        reg [64 : 0] serpens_7;
        reg [64 : 0] tucana_7;
        reg [64 : 0] volans_7;
        reg [64 : 0] vulpecula_7;
        reg [63 : 0] orion_8;
        reg [64 : 0] lyra_8;
        reg [64 : 0] cygnus_8;
        reg [64 : 0] draco_8;
        reg [64 : 0] aquila_8;
        reg [64 : 0] pegasus_8;
        reg [63 : 0] perseus_8;
        reg [64 : 0] andromeda_8;
        reg [64 : 0] phoenix_8;
        reg [64 : 0] hydra_8;
        reg [64 : 0] centaurus_8;
        reg [64 : 0] cassiopeia_8;
        reg [17 : 0] carina_8;
        reg [63 : 0] vela_8;
      
        orion = {64'h1, {(6'h20){1'b0}}};
        num_1 = orion[63 : 0];
        lyra = (num_1 >> 64'h2f);
        cygnus = (lyra[1 : 0] & 2'h1);
        draco = ({1'h0, {(1'h1){1'b0}}} | cygnus[1 : 0]);
        rem_2 = {62'b0, draco};
        aquila = {num_1, {(1'h1){1'b0}}};
        num_2 = aquila[63 : 0];
        pegasus = {1'h0, {(1'h1){1'b0}}};
        q_2 = {62'b0, pegasus};
        if ((rem_2 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          perseus = (rem_2 - $unsigned($signed({{32{d[31]}}, d})));
          rem_4 = perseus[63 : 0];
          q_4 = (q_2 | 64'h1);
        end else begin
          rem_4 = rem_2;
          q_4 = q_2;
        end
        andromeda = {rem_4, {(1'h1){1'b0}}};
        phoenix = (num_2 >> 64'h2f);
        hydra = (andromeda[63 : 0] | (phoenix[16 : 0] & 17'h1));
        rem_5 = hydra[63 : 0];
        centaurus = {num_2, {(1'h1){1'b0}}};
        num_3 = centaurus[63 : 0];
        cassiopeia = {q_4, {(1'h1){1'b0}}};
        q_5 = cassiopeia[63 : 0];
        if ((rem_5 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          carina = (rem_5 - $unsigned($signed({{32{d[31]}}, d})));
          rem_7 = carina[63 : 0];
          q_7 = (q_5 | 64'h1);
        end else begin
          rem_7 = rem_5;
          q_7 = q_5;
        end
        vela = {rem_7, {(1'h1){1'b0}}};
        auriga = (num_3 >> 64'h2f);
        cepheus = (vela[63 : 0] | (auriga[16 : 0] & 17'h1));
        rem_8 = cepheus[63 : 0];
        columba = {num_3, {(1'h1){1'b0}}};
        num_4 = columba[63 : 0];
        corvus = {q_7, {(1'h1){1'b0}}};
        q_8 = corvus[63 : 0];
        if ((rem_8 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          crux = (rem_8 - $unsigned($signed({{32{d[31]}}, d})));
          rem_10 = crux[63 : 0];
          q_10 = (q_8 | 64'h1);
        end else begin
          rem_10 = rem_8;
          q_10 = q_8;
        end
        fornax = {rem_10, {(1'h1){1'b0}}};
        gemini = (num_4 >> 64'h2f);
        hercules = (fornax[63 : 0] | (gemini[16 : 0] & 17'h1));
        rem_11 = hercules[63 : 0];
        indus = {num_4, {(1'h1){1'b0}}};
        num_5 = indus[63 : 0];
        lupus = {q_10, {(1'h1){1'b0}}};
        q_11 = lupus[63 : 0];
        if ((rem_11 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          lynx = (rem_11 - $unsigned($signed({{32{d[31]}}, d})));
          rem_13 = lynx[63 : 0];
          q_13 = (q_11 | 64'h1);
        end else begin
          rem_13 = rem_11;
          q_13 = q_11;
        end
        norma = {rem_13, {(1'h1){1'b0}}};
        octans = (num_5 >> 64'h2f);
        pictor = (norma[63 : 0] | (octans[16 : 0] & 17'h1));
        rem_14 = pictor[63 : 0];
        pyxis = {num_5, {(1'h1){1'b0}}};
        num_6 = pyxis[63 : 0];
        sagitta = {q_13, {(1'h1){1'b0}}};
        q_14 = sagitta[63 : 0];
        if ((rem_14 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          serpens = (rem_14 - $unsigned($signed({{32{d[31]}}, d})));
          rem_16 = serpens[63 : 0];
          q_16 = (q_14 | 64'h1);
        end else begin
          rem_16 = rem_14;
          q_16 = q_14;
        end
        tucana = {rem_16, {(1'h1){1'b0}}};
        volans = (num_6 >> 64'h2f);
        vulpecula = (tucana[63 : 0] | (volans[16 : 0] & 17'h1));
        rem_17 = vulpecula[63 : 0];
        orion_1 = {num_6, {(1'h1){1'b0}}};
        num_7 = orion_1[63 : 0];
        lyra_1 = {q_16, {(1'h1){1'b0}}};
        q_17 = lyra_1[63 : 0];
        if ((rem_17 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          cygnus_1 = (rem_17 - $unsigned($signed({{32{d[31]}}, d})));
          rem_19 = cygnus_1[63 : 0];
          q_19 = (q_17 | 64'h1);
        end else begin
          rem_19 = rem_17;
          q_19 = q_17;
        end
        draco_1 = {rem_19, {(1'h1){1'b0}}};
        aquila_1 = (num_7 >> 64'h2f);
        pegasus_1 = (draco_1[63 : 0] | (aquila_1[16 : 0] & 17'h1));
        rem_20 = pegasus_1[63 : 0];
        perseus_1 = {num_7, {(1'h1){1'b0}}};
        num_8 = perseus_1[63 : 0];
        andromeda_1 = {q_19, {(1'h1){1'b0}}};
        q_20 = andromeda_1[63 : 0];
        if ((rem_20 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          phoenix_1 = (rem_20 - $unsigned($signed({{32{d[31]}}, d})));
          rem_22 = phoenix_1[63 : 0];
          q_22 = (q_20 | 64'h1);
        end else begin
          rem_22 = rem_20;
          q_22 = q_20;
        end
        hydra_1 = {rem_22, {(1'h1){1'b0}}};
        centaurus_1 = (num_8 >> 64'h2f);
        cassiopeia_1 = (hydra_1[63 : 0] | (centaurus_1[16 : 0] & 17'h1));
        rem_23 = cassiopeia_1[63 : 0];
        carina_1 = {num_8, {(1'h1){1'b0}}};
        num_9 = carina_1[63 : 0];
        vela_1 = {q_22, {(1'h1){1'b0}}};
        q_23 = vela_1[63 : 0];
        if ((rem_23 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          auriga_1 = (rem_23 - $unsigned($signed({{32{d[31]}}, d})));
          rem_25 = auriga_1[63 : 0];
          q_25 = (q_23 | 64'h1);
        end else begin
          rem_25 = rem_23;
          q_25 = q_23;
        end
        cepheus_1 = {rem_25, {(1'h1){1'b0}}};
        columba_1 = (num_9 >> 64'h2f);
        corvus_1 = (cepheus_1[63 : 0] | (columba_1[16 : 0] & 17'h1));
        rem_26 = corvus_1[63 : 0];
        crux_1 = {num_9, {(1'h1){1'b0}}};
        num_10 = crux_1[63 : 0];
        fornax_1 = {q_25, {(1'h1){1'b0}}};
        q_26 = fornax_1[63 : 0];
        if ((rem_26 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          gemini_1 = (rem_26 - $unsigned($signed({{32{d[31]}}, d})));
          rem_28 = gemini_1[63 : 0];
          q_28 = (q_26 | 64'h1);
        end else begin
          rem_28 = rem_26;
          q_28 = q_26;
        end
        hercules_1 = {rem_28, {(1'h1){1'b0}}};
        indus_1 = (num_10 >> 64'h2f);
        lupus_1 = (hercules_1[63 : 0] | (indus_1[16 : 0] & 17'h1));
        rem_29 = lupus_1[63 : 0];
        lynx_1 = {num_10, {(1'h1){1'b0}}};
        num_11 = lynx_1[63 : 0];
        norma_1 = {q_28, {(1'h1){1'b0}}};
        q_29 = norma_1[63 : 0];
        if ((rem_29 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          octans_1 = (rem_29 - $unsigned($signed({{32{d[31]}}, d})));
          rem_31 = octans_1[63 : 0];
          q_31 = (q_29 | 64'h1);
        end else begin
          rem_31 = rem_29;
          q_31 = q_29;
        end
        pictor_1 = {rem_31, {(1'h1){1'b0}}};
        pyxis_1 = (num_11 >> 64'h2f);
        sagitta_1 = (pictor_1[63 : 0] | (pyxis_1[16 : 0] & 17'h1));
        rem_32 = sagitta_1[63 : 0];
        serpens_1 = {num_11, {(1'h1){1'b0}}};
        num_12 = serpens_1[63 : 0];
        tucana_1 = {q_31, {(1'h1){1'b0}}};
        q_32 = tucana_1[63 : 0];
        if ((rem_32 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          volans_1 = (rem_32 - $unsigned($signed({{32{d[31]}}, d})));
          rem_34 = volans_1[63 : 0];
          q_34 = (q_32 | 64'h1);
        end else begin
          rem_34 = rem_32;
          q_34 = q_32;
        end
        vulpecula_1 = {rem_34, {(1'h1){1'b0}}};
        orion_2 = (num_12 >> 64'h2f);
        lyra_2 = (vulpecula_1[63 : 0] | (orion_2[16 : 0] & 17'h1));
        rem_35 = lyra_2[63 : 0];
        cygnus_2 = {num_12, {(1'h1){1'b0}}};
        num_13 = cygnus_2[63 : 0];
        draco_2 = {q_34, {(1'h1){1'b0}}};
        q_35 = draco_2[63 : 0];
        if ((rem_35 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          aquila_2 = (rem_35 - $unsigned($signed({{32{d[31]}}, d})));
          rem_37 = aquila_2[63 : 0];
          q_37 = (q_35 | 64'h1);
        end else begin
          rem_37 = rem_35;
          q_37 = q_35;
        end
        pegasus_2 = {rem_37, {(1'h1){1'b0}}};
        perseus_2 = (num_13 >> 64'h2f);
        andromeda_2 = (pegasus_2[63 : 0] | (perseus_2[16 : 0] & 17'h1));
        rem_38 = andromeda_2[63 : 0];
        phoenix_2 = {num_13, {(1'h1){1'b0}}};
        num_14 = phoenix_2[63 : 0];
        hydra_2 = {q_37, {(1'h1){1'b0}}};
        q_38 = hydra_2[63 : 0];
        if ((rem_38 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          centaurus_2 = (rem_38 - $unsigned($signed({{32{d[31]}}, d})));
          rem_40 = centaurus_2[63 : 0];
          q_40 = (q_38 | 64'h1);
        end else begin
          rem_40 = rem_38;
          q_40 = q_38;
        end
        cassiopeia_2 = {rem_40, {(1'h1){1'b0}}};
        carina_2 = (num_14 >> 64'h2f);
        vela_2 = (cassiopeia_2[63 : 0] | (carina_2[16 : 0] & 17'h1));
        rem_41 = vela_2[63 : 0];
        auriga_2 = {num_14, {(1'h1){1'b0}}};
        num_15 = auriga_2[63 : 0];
        cepheus_2 = {q_40, {(1'h1){1'b0}}};
        q_41 = cepheus_2[63 : 0];
        if ((rem_41 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          columba_2 = (rem_41 - $unsigned($signed({{32{d[31]}}, d})));
          rem_43 = columba_2[63 : 0];
          q_43 = (q_41 | 64'h1);
        end else begin
          rem_43 = rem_41;
          q_43 = q_41;
        end
        corvus_2 = {rem_43, {(1'h1){1'b0}}};
        crux_2 = (num_15 >> 64'h2f);
        fornax_2 = (corvus_2[63 : 0] | (crux_2[16 : 0] & 17'h1));
        rem_44 = fornax_2[63 : 0];
        gemini_2 = {num_15, {(1'h1){1'b0}}};
        num_16 = gemini_2[63 : 0];
        hercules_2 = {q_43, {(1'h1){1'b0}}};
        q_44 = hercules_2[63 : 0];
        if ((rem_44 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          indus_2 = (rem_44 - $unsigned($signed({{32{d[31]}}, d})));
          rem_46 = indus_2[63 : 0];
          q_46 = (q_44 | 64'h1);
        end else begin
          rem_46 = rem_44;
          q_46 = q_44;
        end
        lupus_2 = {rem_46, {(1'h1){1'b0}}};
        lynx_2 = (num_16 >> 64'h2f);
        norma_2 = (lupus_2[63 : 0] | (lynx_2[16 : 0] & 17'h1));
        rem_47 = norma_2[63 : 0];
        octans_2 = {num_16, {(1'h1){1'b0}}};
        num_17 = octans_2[63 : 0];
        pictor_2 = {q_46, {(1'h1){1'b0}}};
        q_47 = pictor_2[63 : 0];
        if ((rem_47 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          pyxis_2 = (rem_47 - $unsigned($signed({{32{d[31]}}, d})));
          rem_49 = pyxis_2[63 : 0];
          q_49 = (q_47 | 64'h1);
        end else begin
          rem_49 = rem_47;
          q_49 = q_47;
        end
        sagitta_2 = {rem_49, {(1'h1){1'b0}}};
        serpens_2 = (num_17 >> 64'h2f);
        tucana_2 = (sagitta_2[63 : 0] | (serpens_2[16 : 0] & 17'h1));
        rem_50 = tucana_2[63 : 0];
        volans_2 = {num_17, {(1'h1){1'b0}}};
        num_18 = volans_2[63 : 0];
        vulpecula_2 = {q_49, {(1'h1){1'b0}}};
        q_50 = vulpecula_2[63 : 0];
        if ((rem_50 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          orion_3 = (rem_50 - $unsigned($signed({{32{d[31]}}, d})));
          rem_52 = orion_3[63 : 0];
          q_52 = (q_50 | 64'h1);
        end else begin
          rem_52 = rem_50;
          q_52 = q_50;
        end
        lyra_3 = {rem_52, {(1'h1){1'b0}}};
        cygnus_3 = (num_18 >> 64'h2f);
        draco_3 = (lyra_3[63 : 0] | (cygnus_3[16 : 0] & 17'h1));
        rem_53 = draco_3[63 : 0];
        aquila_3 = {num_18, {(1'h1){1'b0}}};
        num_19 = aquila_3[63 : 0];
        pegasus_3 = {q_52, {(1'h1){1'b0}}};
        q_53 = pegasus_3[63 : 0];
        if ((rem_53 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          perseus_3 = (rem_53 - $unsigned($signed({{32{d[31]}}, d})));
          rem_55 = perseus_3[63 : 0];
          q_55 = (q_53 | 64'h1);
        end else begin
          rem_55 = rem_53;
          q_55 = q_53;
        end
        andromeda_3 = {rem_55, {(1'h1){1'b0}}};
        phoenix_3 = (num_19 >> 64'h2f);
        hydra_3 = (andromeda_3[63 : 0] | (phoenix_3[16 : 0] & 17'h1));
        rem_56 = hydra_3[63 : 0];
        centaurus_3 = {num_19, {(1'h1){1'b0}}};
        num_20 = centaurus_3[63 : 0];
        cassiopeia_3 = {q_55, {(1'h1){1'b0}}};
        q_56 = cassiopeia_3[63 : 0];
        if ((rem_56 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          carina_3 = (rem_56 - $unsigned($signed({{32{d[31]}}, d})));
          rem_58 = carina_3[63 : 0];
          q_58 = (q_56 | 64'h1);
        end else begin
          rem_58 = rem_56;
          q_58 = q_56;
        end
        vela_3 = {rem_58, {(1'h1){1'b0}}};
        auriga_3 = (num_20 >> 64'h2f);
        cepheus_3 = (vela_3[63 : 0] | (auriga_3[16 : 0] & 17'h1));
        rem_59 = cepheus_3[63 : 0];
        columba_3 = {num_20, {(1'h1){1'b0}}};
        num_21 = columba_3[63 : 0];
        corvus_3 = {q_58, {(1'h1){1'b0}}};
        q_59 = corvus_3[63 : 0];
        if ((rem_59 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          crux_3 = (rem_59 - $unsigned($signed({{32{d[31]}}, d})));
          rem_61 = crux_3[63 : 0];
          q_61 = (q_59 | 64'h1);
        end else begin
          rem_61 = rem_59;
          q_61 = q_59;
        end
        fornax_3 = {rem_61, {(1'h1){1'b0}}};
        gemini_3 = (num_21 >> 64'h2f);
        hercules_3 = (fornax_3[63 : 0] | (gemini_3[16 : 0] & 17'h1));
        rem_62 = hercules_3[63 : 0];
        indus_3 = {num_21, {(1'h1){1'b0}}};
        num_22 = indus_3[63 : 0];
        lupus_3 = {q_61, {(1'h1){1'b0}}};
        q_62 = lupus_3[63 : 0];
        if ((rem_62 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          lynx_3 = (rem_62 - $unsigned($signed({{32{d[31]}}, d})));
          rem_64 = lynx_3[63 : 0];
          q_64 = (q_62 | 64'h1);
        end else begin
          rem_64 = rem_62;
          q_64 = q_62;
        end
        norma_3 = {rem_64, {(1'h1){1'b0}}};
        octans_3 = (num_22 >> 64'h2f);
        pictor_3 = (norma_3[63 : 0] | (octans_3[16 : 0] & 17'h1));
        rem_65 = pictor_3[63 : 0];
        pyxis_3 = {num_22, {(1'h1){1'b0}}};
        num_23 = pyxis_3[63 : 0];
        sagitta_3 = {q_64, {(1'h1){1'b0}}};
        q_65 = sagitta_3[63 : 0];
        if ((rem_65 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          serpens_3 = (rem_65 - $unsigned($signed({{32{d[31]}}, d})));
          rem_67 = serpens_3[63 : 0];
          q_67 = (q_65 | 64'h1);
        end else begin
          rem_67 = rem_65;
          q_67 = q_65;
        end
        tucana_3 = {rem_67, {(1'h1){1'b0}}};
        volans_3 = (num_23 >> 64'h2f);
        vulpecula_3 = (tucana_3[63 : 0] | (volans_3[16 : 0] & 17'h1));
        rem_68 = vulpecula_3[63 : 0];
        orion_4 = {num_23, {(1'h1){1'b0}}};
        num_24 = orion_4[63 : 0];
        lyra_4 = {q_67, {(1'h1){1'b0}}};
        q_68 = lyra_4[63 : 0];
        if ((rem_68 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          cygnus_4 = (rem_68 - $unsigned($signed({{32{d[31]}}, d})));
          rem_70 = cygnus_4[63 : 0];
          q_70 = (q_68 | 64'h1);
        end else begin
          rem_70 = rem_68;
          q_70 = q_68;
        end
        draco_4 = {rem_70, {(1'h1){1'b0}}};
        aquila_4 = (num_24 >> 64'h2f);
        pegasus_4 = (draco_4[63 : 0] | (aquila_4[16 : 0] & 17'h1));
        rem_71 = pegasus_4[63 : 0];
        perseus_4 = {num_24, {(1'h1){1'b0}}};
        num_25 = perseus_4[63 : 0];
        andromeda_4 = {q_70, {(1'h1){1'b0}}};
        q_71 = andromeda_4[63 : 0];
        if ((rem_71 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          phoenix_4 = (rem_71 - $unsigned($signed({{32{d[31]}}, d})));
          rem_73 = phoenix_4[63 : 0];
          q_73 = (q_71 | 64'h1);
        end else begin
          rem_73 = rem_71;
          q_73 = q_71;
        end
        hydra_4 = {rem_73, {(1'h1){1'b0}}};
        centaurus_4 = (num_25 >> 64'h2f);
        cassiopeia_4 = (hydra_4[63 : 0] | (centaurus_4[16 : 0] & 17'h1));
        rem_74 = cassiopeia_4[63 : 0];
        carina_4 = {num_25, {(1'h1){1'b0}}};
        num_26 = carina_4[63 : 0];
        vela_4 = {q_73, {(1'h1){1'b0}}};
        q_74 = vela_4[63 : 0];
        if ((rem_74 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          auriga_4 = (rem_74 - $unsigned($signed({{32{d[31]}}, d})));
          rem_76 = auriga_4[63 : 0];
          q_76 = (q_74 | 64'h1);
        end else begin
          rem_76 = rem_74;
          q_76 = q_74;
        end
        cepheus_4 = {rem_76, {(1'h1){1'b0}}};
        columba_4 = (num_26 >> 64'h2f);
        corvus_4 = (cepheus_4[63 : 0] | (columba_4[16 : 0] & 17'h1));
        rem_77 = corvus_4[63 : 0];
        crux_4 = {num_26, {(1'h1){1'b0}}};
        num_27 = crux_4[63 : 0];
        fornax_4 = {q_76, {(1'h1){1'b0}}};
        q_77 = fornax_4[63 : 0];
        if ((rem_77 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          gemini_4 = (rem_77 - $unsigned($signed({{32{d[31]}}, d})));
          rem_79 = gemini_4[63 : 0];
          q_79 = (q_77 | 64'h1);
        end else begin
          rem_79 = rem_77;
          q_79 = q_77;
        end
        hercules_4 = {rem_79, {(1'h1){1'b0}}};
        indus_4 = (num_27 >> 64'h2f);
        lupus_4 = (hercules_4[63 : 0] | (indus_4[16 : 0] & 17'h1));
        rem_80 = lupus_4[63 : 0];
        lynx_4 = {num_27, {(1'h1){1'b0}}};
        num_28 = lynx_4[63 : 0];
        norma_4 = {q_79, {(1'h1){1'b0}}};
        q_80 = norma_4[63 : 0];
        if ((rem_80 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          octans_4 = (rem_80 - $unsigned($signed({{32{d[31]}}, d})));
          rem_82 = octans_4[63 : 0];
          q_82 = (q_80 | 64'h1);
        end else begin
          rem_82 = rem_80;
          q_82 = q_80;
        end
        pictor_4 = {rem_82, {(1'h1){1'b0}}};
        pyxis_4 = (num_28 >> 64'h2f);
        sagitta_4 = (pictor_4[63 : 0] | (pyxis_4[16 : 0] & 17'h1));
        rem_83 = sagitta_4[63 : 0];
        serpens_4 = {num_28, {(1'h1){1'b0}}};
        num_29 = serpens_4[63 : 0];
        tucana_4 = {q_82, {(1'h1){1'b0}}};
        q_83 = tucana_4[63 : 0];
        if ((rem_83 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          volans_4 = (rem_83 - $unsigned($signed({{32{d[31]}}, d})));
          rem_85 = volans_4[63 : 0];
          q_85 = (q_83 | 64'h1);
        end else begin
          rem_85 = rem_83;
          q_85 = q_83;
        end
        vulpecula_4 = {rem_85, {(1'h1){1'b0}}};
        orion_5 = (num_29 >> 64'h2f);
        lyra_5 = (vulpecula_4[63 : 0] | (orion_5[16 : 0] & 17'h1));
        rem_86 = lyra_5[63 : 0];
        cygnus_5 = {num_29, {(1'h1){1'b0}}};
        num_30 = cygnus_5[63 : 0];
        draco_5 = {q_85, {(1'h1){1'b0}}};
        q_86 = draco_5[63 : 0];
        if ((rem_86 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          aquila_5 = (rem_86 - $unsigned($signed({{32{d[31]}}, d})));
          rem_88 = aquila_5[63 : 0];
          q_88 = (q_86 | 64'h1);
        end else begin
          rem_88 = rem_86;
          q_88 = q_86;
        end
        pegasus_5 = {rem_88, {(1'h1){1'b0}}};
        perseus_5 = (num_30 >> 64'h2f);
        andromeda_5 = (pegasus_5[63 : 0] | (perseus_5[16 : 0] & 17'h1));
        rem_89 = andromeda_5[63 : 0];
        phoenix_5 = {num_30, {(1'h1){1'b0}}};
        num_31 = phoenix_5[63 : 0];
        hydra_5 = {q_88, {(1'h1){1'b0}}};
        q_89 = hydra_5[63 : 0];
        if ((rem_89 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          centaurus_5 = (rem_89 - $unsigned($signed({{32{d[31]}}, d})));
          rem_91 = centaurus_5[63 : 0];
          q_91 = (q_89 | 64'h1);
        end else begin
          rem_91 = rem_89;
          q_91 = q_89;
        end
        cassiopeia_5 = {rem_91, {(1'h1){1'b0}}};
        carina_5 = (num_31 >> 64'h2f);
        vela_5 = (cassiopeia_5[63 : 0] | (carina_5[16 : 0] & 17'h1));
        rem_92 = vela_5[63 : 0];
        auriga_5 = {num_31, {(1'h1){1'b0}}};
        num_32 = auriga_5[63 : 0];
        cepheus_5 = {q_91, {(1'h1){1'b0}}};
        q_92 = cepheus_5[63 : 0];
        if ((rem_92 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          columba_5 = (rem_92 - $unsigned($signed({{32{d[31]}}, d})));
          rem_94 = columba_5[63 : 0];
          q_94 = (q_92 | 64'h1);
        end else begin
          rem_94 = rem_92;
          q_94 = q_92;
        end
        corvus_5 = {rem_94, {(1'h1){1'b0}}};
        crux_5 = (num_32 >> 64'h2f);
        fornax_5 = (corvus_5[63 : 0] | (crux_5[16 : 0] & 17'h1));
        rem_95 = fornax_5[63 : 0];
        gemini_5 = {num_32, {(1'h1){1'b0}}};
        num_33 = gemini_5[63 : 0];
        hercules_5 = {q_94, {(1'h1){1'b0}}};
        q_95 = hercules_5[63 : 0];
        if ((rem_95 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          indus_5 = (rem_95 - $unsigned($signed({{32{d[31]}}, d})));
          rem_97 = indus_5[63 : 0];
          q_97 = (q_95 | 64'h1);
        end else begin
          rem_97 = rem_95;
          q_97 = q_95;
        end
        lupus_5 = {rem_97, {(1'h1){1'b0}}};
        lynx_5 = (num_33 >> 64'h2f);
        norma_5 = (lupus_5[63 : 0] | (lynx_5[16 : 0] & 17'h1));
        rem_98 = norma_5[63 : 0];
        octans_5 = {num_33, {(1'h1){1'b0}}};
        num_34 = octans_5[63 : 0];
        pictor_5 = {q_97, {(1'h1){1'b0}}};
        q_98 = pictor_5[63 : 0];
        if ((rem_98 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          pyxis_5 = (rem_98 - $unsigned($signed({{32{d[31]}}, d})));
          rem_100 = pyxis_5[63 : 0];
          q_100 = (q_98 | 64'h1);
        end else begin
          rem_100 = rem_98;
          q_100 = q_98;
        end
        sagitta_5 = {rem_100, {(1'h1){1'b0}}};
        serpens_5 = (num_34 >> 64'h2f);
        tucana_5 = (sagitta_5[63 : 0] | (serpens_5[16 : 0] & 17'h1));
        rem_101 = tucana_5[63 : 0];
        volans_5 = {num_34, {(1'h1){1'b0}}};
        num_35 = volans_5[63 : 0];
        vulpecula_5 = {q_100, {(1'h1){1'b0}}};
        q_101 = vulpecula_5[63 : 0];
        if ((rem_101 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          orion_6 = (rem_101 - $unsigned($signed({{32{d[31]}}, d})));
          rem_103 = orion_6[63 : 0];
          q_103 = (q_101 | 64'h1);
        end else begin
          rem_103 = rem_101;
          q_103 = q_101;
        end
        lyra_6 = {rem_103, {(1'h1){1'b0}}};
        cygnus_6 = (num_35 >> 64'h2f);
        draco_6 = (lyra_6[63 : 0] | (cygnus_6[16 : 0] & 17'h1));
        rem_104 = draco_6[63 : 0];
        aquila_6 = {num_35, {(1'h1){1'b0}}};
        num_36 = aquila_6[63 : 0];
        pegasus_6 = {q_103, {(1'h1){1'b0}}};
        q_104 = pegasus_6[63 : 0];
        if ((rem_104 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          perseus_6 = (rem_104 - $unsigned($signed({{32{d[31]}}, d})));
          rem_106 = perseus_6[63 : 0];
          q_106 = (q_104 | 64'h1);
        end else begin
          rem_106 = rem_104;
          q_106 = q_104;
        end
        andromeda_6 = {rem_106, {(1'h1){1'b0}}};
        phoenix_6 = (num_36 >> 64'h2f);
        hydra_6 = (andromeda_6[63 : 0] | (phoenix_6[16 : 0] & 17'h1));
        rem_107 = hydra_6[63 : 0];
        centaurus_6 = {num_36, {(1'h1){1'b0}}};
        num_37 = centaurus_6[63 : 0];
        cassiopeia_6 = {q_106, {(1'h1){1'b0}}};
        q_107 = cassiopeia_6[63 : 0];
        if ((rem_107 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          carina_6 = (rem_107 - $unsigned($signed({{32{d[31]}}, d})));
          rem_109 = carina_6[63 : 0];
          q_109 = (q_107 | 64'h1);
        end else begin
          rem_109 = rem_107;
          q_109 = q_107;
        end
        vela_6 = {rem_109, {(1'h1){1'b0}}};
        auriga_6 = (num_37 >> 64'h2f);
        cepheus_6 = (vela_6[63 : 0] | (auriga_6[16 : 0] & 17'h1));
        rem_110 = cepheus_6[63 : 0];
        columba_6 = {num_37, {(1'h1){1'b0}}};
        num_38 = columba_6[63 : 0];
        corvus_6 = {q_109, {(1'h1){1'b0}}};
        q_110 = corvus_6[63 : 0];
        if ((rem_110 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          crux_6 = (rem_110 - $unsigned($signed({{32{d[31]}}, d})));
          rem_112 = crux_6[63 : 0];
          q_112 = (q_110 | 64'h1);
        end else begin
          rem_112 = rem_110;
          q_112 = q_110;
        end
        fornax_6 = {rem_112, {(1'h1){1'b0}}};
        gemini_6 = (num_38 >> 64'h2f);
        hercules_6 = (fornax_6[63 : 0] | (gemini_6[16 : 0] & 17'h1));
        rem_113 = hercules_6[63 : 0];
        indus_6 = {num_38, {(1'h1){1'b0}}};
        num_39 = indus_6[63 : 0];
        lupus_6 = {q_112, {(1'h1){1'b0}}};
        q_113 = lupus_6[63 : 0];
        if ((rem_113 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          lynx_6 = (rem_113 - $unsigned($signed({{32{d[31]}}, d})));
          rem_115 = lynx_6[63 : 0];
          q_115 = (q_113 | 64'h1);
        end else begin
          rem_115 = rem_113;
          q_115 = q_113;
        end
        norma_6 = {rem_115, {(1'h1){1'b0}}};
        octans_6 = (num_39 >> 64'h2f);
        pictor_6 = (norma_6[63 : 0] | (octans_6[16 : 0] & 17'h1));
        rem_116 = pictor_6[63 : 0];
        pyxis_6 = {num_39, {(1'h1){1'b0}}};
        num_40 = pyxis_6[63 : 0];
        sagitta_6 = {q_115, {(1'h1){1'b0}}};
        q_116 = sagitta_6[63 : 0];
        if ((rem_116 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          serpens_6 = (rem_116 - $unsigned($signed({{32{d[31]}}, d})));
          rem_118 = serpens_6[63 : 0];
          q_118 = (q_116 | 64'h1);
        end else begin
          rem_118 = rem_116;
          q_118 = q_116;
        end
        tucana_6 = {rem_118, {(1'h1){1'b0}}};
        volans_6 = (num_40 >> 64'h2f);
        vulpecula_6 = (tucana_6[63 : 0] | (volans_6[16 : 0] & 17'h1));
        rem_119 = vulpecula_6[63 : 0];
        orion_7 = {num_40, {(1'h1){1'b0}}};
        num_41 = orion_7[63 : 0];
        lyra_7 = {q_118, {(1'h1){1'b0}}};
        q_119 = lyra_7[63 : 0];
        if ((rem_119 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          cygnus_7 = (rem_119 - $unsigned($signed({{32{d[31]}}, d})));
          rem_121 = cygnus_7[63 : 0];
          q_121 = (q_119 | 64'h1);
        end else begin
          rem_121 = rem_119;
          q_121 = q_119;
        end
        draco_7 = {rem_121, {(1'h1){1'b0}}};
        aquila_7 = (num_41 >> 64'h2f);
        pegasus_7 = (draco_7[63 : 0] | (aquila_7[16 : 0] & 17'h1));
        rem_122 = pegasus_7[63 : 0];
        perseus_7 = {num_41, {(1'h1){1'b0}}};
        num_42 = perseus_7[63 : 0];
        andromeda_7 = {q_121, {(1'h1){1'b0}}};
        q_122 = andromeda_7[63 : 0];
        if ((rem_122 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          phoenix_7 = (rem_122 - $unsigned($signed({{32{d[31]}}, d})));
          rem_124 = phoenix_7[63 : 0];
          q_124 = (q_122 | 64'h1);
        end else begin
          rem_124 = rem_122;
          q_124 = q_122;
        end
        hydra_7 = {rem_124, {(1'h1){1'b0}}};
        centaurus_7 = (num_42 >> 64'h2f);
        cassiopeia_7 = (hydra_7[63 : 0] | (centaurus_7[16 : 0] & 17'h1));
        rem_125 = cassiopeia_7[63 : 0];
        carina_7 = {num_42, {(1'h1){1'b0}}};
        num_43 = carina_7[63 : 0];
        vela_7 = {q_124, {(1'h1){1'b0}}};
        q_125 = vela_7[63 : 0];
        if ((rem_125 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          auriga_7 = (rem_125 - $unsigned($signed({{32{d[31]}}, d})));
          rem_127 = auriga_7[63 : 0];
          q_127 = (q_125 | 64'h1);
        end else begin
          rem_127 = rem_125;
          q_127 = q_125;
        end
        cepheus_7 = {rem_127, {(1'h1){1'b0}}};
        columba_7 = (num_43 >> 64'h2f);
        corvus_7 = (cepheus_7[63 : 0] | (columba_7[16 : 0] & 17'h1));
        rem_128 = corvus_7[63 : 0];
        crux_7 = {num_43, {(1'h1){1'b0}}};
        num_44 = crux_7[63 : 0];
        fornax_7 = {q_127, {(1'h1){1'b0}}};
        q_128 = fornax_7[63 : 0];
        if ((rem_128 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          gemini_7 = (rem_128 - $unsigned($signed({{32{d[31]}}, d})));
          rem_130 = gemini_7[63 : 0];
          q_130 = (q_128 | 64'h1);
        end else begin
          rem_130 = rem_128;
          q_130 = q_128;
        end
        hercules_7 = {rem_130, {(1'h1){1'b0}}};
        indus_7 = (num_44 >> 64'h2f);
        lupus_7 = (hercules_7[63 : 0] | (indus_7[16 : 0] & 17'h1));
        rem_131 = lupus_7[63 : 0];
        lynx_7 = {num_44, {(1'h1){1'b0}}};
        num_45 = lynx_7[63 : 0];
        norma_7 = {q_130, {(1'h1){1'b0}}};
        q_131 = norma_7[63 : 0];
        if ((rem_131 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          octans_7 = (rem_131 - $unsigned($signed({{32{d[31]}}, d})));
          rem_133 = octans_7[63 : 0];
          q_133 = (q_131 | 64'h1);
        end else begin
          rem_133 = rem_131;
          q_133 = q_131;
        end
        pictor_7 = {rem_133, {(1'h1){1'b0}}};
        pyxis_7 = (num_45 >> 64'h2f);
        sagitta_7 = (pictor_7[63 : 0] | (pyxis_7[16 : 0] & 17'h1));
        rem_134 = sagitta_7[63 : 0];
        serpens_7 = {num_45, {(1'h1){1'b0}}};
        num_46 = serpens_7[63 : 0];
        tucana_7 = {q_133, {(1'h1){1'b0}}};
        q_134 = tucana_7[63 : 0];
        if ((rem_134 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          volans_7 = (rem_134 - $unsigned($signed({{32{d[31]}}, d})));
          rem_136 = volans_7[63 : 0];
          q_136 = (q_134 | 64'h1);
        end else begin
          rem_136 = rem_134;
          q_136 = q_134;
        end
        vulpecula_7 = {rem_136, {(1'h1){1'b0}}};
        orion_8 = (num_46 >> 64'h2f);
        lyra_8 = (vulpecula_7[63 : 0] | (orion_8[16 : 0] & 17'h1));
        rem_137 = lyra_8[63 : 0];
        cygnus_8 = {num_46, {(1'h1){1'b0}}};
        num_47 = cygnus_8[63 : 0];
        draco_8 = {q_136, {(1'h1){1'b0}}};
        q_137 = draco_8[63 : 0];
        if ((rem_137 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          aquila_8 = (rem_137 - $unsigned($signed({{32{d[31]}}, d})));
          rem_139 = aquila_8[63 : 0];
          q_139 = (q_137 | 64'h1);
        end else begin
          rem_139 = rem_137;
          q_139 = q_137;
        end
        pegasus_8 = {rem_139, {(1'h1){1'b0}}};
        perseus_8 = (num_47 >> 64'h2f);
        andromeda_8 = (pegasus_8[63 : 0] | (perseus_8[16 : 0] & 17'h1));
        rem_140 = andromeda_8[63 : 0];
        phoenix_8 = {q_139, {(1'h1){1'b0}}};
        q_140 = phoenix_8[63 : 0];
        if ((rem_140 >= $unsigned($signed({{32{d[31]}}, d})))) begin
          hydra_8 = (rem_140 - $unsigned($signed({{32{d[31]}}, d})));
          rem_142 = hydra_8[63 : 0];
          q_142 = (q_140 | 64'h1);
        end else begin
          rem_142 = rem_140;
          q_142 = q_140;
        end
        centaurus_8 = {q_142, {(1'h1){1'b0}}};
        q_143 = centaurus_8[63 : 0];
        cassiopeia_8 = ({num_47, {(1'h1){1'b0}}} >> 65'h2f);
        carina_8 = (cassiopeia_8[17 : 0] & 18'h1);
        vela_8 = $unsigned($signed({{32{d[31]}}, d}));
        if ((({rem_142, {(1'h1){1'b0}}} | {47'b0, carina_8}) >= {1'b0, vela_8})) begin
          q_145 = (q_143 | 64'h1);
        end else begin
          q_145 = q_143;
        end
        inv <= $signed(q_145[31 : 0]);
        inv_valid <= 1'b1;
      end
    end
  end

endmodule //Recip
