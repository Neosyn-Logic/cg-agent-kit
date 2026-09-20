
/**
 * Q16.16 isqrt, PORT-DRIVEN (x on a push port) so the datapath survives synthesis.
 */
module FixedSqrt(input clock, input reset_n, input signed [31 : 0] x, input x_valid, output reg signed [31 : 0] result, output reg result_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of FixedSqrt
    if (~reset_n) begin
      result <= 32'b0;
      result_valid <= 1'b0;
    end else begin
      result_valid <= 1'b0;
      
      if (x_valid) begin : FSM_FixedSqrt_a // line 7
        reg [63 : 0] n_1;
        reg [63 : 0] bit_1;
        reg [63 : 0] n_3;
        reg [63 : 0] res_3;
        reg [63 : 0] bit_2;
        reg [63 : 0] n_5;
        reg [63 : 0] res_6;
        reg [63 : 0] bit_3;
        reg [63 : 0] n_7;
        reg [63 : 0] res_9;
        reg [63 : 0] bit_4;
        reg [63 : 0] n_9;
        reg [63 : 0] res_12;
        reg [63 : 0] bit_5;
        reg [63 : 0] n_11;
        reg [63 : 0] res_15;
        reg [63 : 0] bit_6;
        reg [63 : 0] n_13;
        reg [63 : 0] res_18;
        reg [63 : 0] bit_7;
        reg [63 : 0] n_15;
        reg [63 : 0] res_21;
        reg [63 : 0] bit_8;
        reg [63 : 0] n_17;
        reg [63 : 0] res_24;
        reg [63 : 0] bit_9;
        reg [63 : 0] n_19;
        reg [63 : 0] res_27;
        reg [63 : 0] bit_10;
        reg [63 : 0] n_21;
        reg [63 : 0] res_30;
        reg [63 : 0] bit_11;
        reg [63 : 0] n_23;
        reg [63 : 0] res_33;
        reg [63 : 0] bit_12;
        reg [63 : 0] n_25;
        reg [63 : 0] res_36;
        reg [63 : 0] bit_13;
        reg [63 : 0] n_27;
        reg [63 : 0] res_39;
        reg [63 : 0] bit_14;
        reg [63 : 0] n_29;
        reg [63 : 0] res_42;
        reg [63 : 0] bit_15;
        reg [63 : 0] n_31;
        reg [63 : 0] res_45;
        reg [63 : 0] bit_16;
        reg [63 : 0] n_33;
        reg [63 : 0] res_48;
        reg [63 : 0] bit_17;
        reg [63 : 0] n_35;
        reg [63 : 0] res_51;
        reg [63 : 0] bit_18;
        reg [63 : 0] n_37;
        reg [63 : 0] res_54;
        reg [63 : 0] bit_19;
        reg [63 : 0] n_39;
        reg [63 : 0] res_57;
        reg [63 : 0] bit_20;
        reg [63 : 0] n_41;
        reg [63 : 0] res_60;
        reg [63 : 0] bit_21;
        reg [63 : 0] n_43;
        reg [63 : 0] res_63;
        reg [63 : 0] bit_22;
        reg [63 : 0] n_45;
        reg [63 : 0] res_66;
        reg [63 : 0] bit_23;
        reg [63 : 0] n_47;
        reg [63 : 0] res_69;
        reg [63 : 0] bit_24;
        reg [63 : 0] res_72;
        reg [79 : 0] orion;
        reg [109 : 0] lyra;
        reg [65 : 0] cygnus;
        reg [64 : 0] draco;
        reg [0 : 0] aquila;
        reg [65 : 0] pegasus;
        reg [64 : 0] perseus;
        reg [65 : 0] andromeda;
        reg [64 : 0] phoenix;
        reg [65 : 0] hydra;
        reg [64 : 0] centaurus;
        reg [65 : 0] cassiopeia;
        reg [64 : 0] carina;
        reg [65 : 0] vela;
        reg [64 : 0] auriga;
        reg [65 : 0] cepheus;
        reg [64 : 0] columba;
        reg [65 : 0] corvus;
        reg [64 : 0] crux;
        reg [65 : 0] fornax;
        reg [64 : 0] gemini;
        reg [65 : 0] hercules;
        reg [64 : 0] indus;
        reg [65 : 0] lupus;
        reg [64 : 0] lynx;
        reg [65 : 0] norma;
        reg [64 : 0] octans;
        reg [65 : 0] pictor;
        reg [64 : 0] pyxis;
        reg [65 : 0] sagitta;
        reg [64 : 0] serpens;
        reg [65 : 0] tucana;
        reg [64 : 0] volans;
        reg [65 : 0] vulpecula;
        reg [64 : 0] orion_1;
        reg [65 : 0] lyra_1;
        reg [64 : 0] cygnus_1;
        reg [65 : 0] draco_1;
        reg [64 : 0] aquila_1;
        reg [65 : 0] pegasus_1;
        reg [64 : 0] perseus_1;
        reg [65 : 0] andromeda_1;
        reg [64 : 0] phoenix_1;
        reg [65 : 0] hydra_1;
        reg [64 : 0] centaurus_1;
        reg [65 : 0] cassiopeia_1;
        reg [64 : 0] carina_1;
        reg [65 : 0] vela_1;
        reg [64 : 0] auriga_1;
        reg [64 : 0] cepheus_1;
      
        orion = {$unsigned($signed({{32{x[31]}}, x})), {(5'h10){1'b0}}};
        n_1 = orion[63 : 0];
        lyra = {64'h1, {(6'h2e){1'b0}}};
        bit_1 = lyra[63 : 0];
        if (({1'b0, n_1} >= (65'h0 + {1'b0, bit_1}))) begin
          cygnus = (n_1 - (64'h0 + bit_1));
          n_3 = cygnus[63 : 0];
          draco = ((1'h0 >> 1'h1) + bit_1);
          res_3 = draco[63 : 0];
        end else begin
          n_3 = n_1;
          aquila = (1'h0 >> 1'h1);
          res_3 = {63'b0, aquila};
        end
        bit_2 = (bit_1 >> 64'h2);
        if (({1'b0, n_3} >= ({1'b0, res_3} + {1'b0, bit_2}))) begin
          pegasus = (n_3 - (res_3 + bit_2));
          n_5 = pegasus[63 : 0];
          perseus = ((res_3 >> 64'h1) + bit_2);
          res_6 = perseus[63 : 0];
        end else begin
          n_5 = n_3;
          res_6 = (res_3 >> 64'h1);
        end
        bit_3 = (bit_2 >> 64'h2);
        if (({1'b0, n_5} >= ({1'b0, res_6} + {1'b0, bit_3}))) begin
          andromeda = (n_5 - (res_6 + bit_3));
          n_7 = andromeda[63 : 0];
          phoenix = ((res_6 >> 64'h1) + bit_3);
          res_9 = phoenix[63 : 0];
        end else begin
          n_7 = n_5;
          res_9 = (res_6 >> 64'h1);
        end
        bit_4 = (bit_3 >> 64'h2);
        if (({1'b0, n_7} >= ({1'b0, res_9} + {1'b0, bit_4}))) begin
          hydra = (n_7 - (res_9 + bit_4));
          n_9 = hydra[63 : 0];
          centaurus = ((res_9 >> 64'h1) + bit_4);
          res_12 = centaurus[63 : 0];
        end else begin
          n_9 = n_7;
          res_12 = (res_9 >> 64'h1);
        end
        bit_5 = (bit_4 >> 64'h2);
        if (({1'b0, n_9} >= ({1'b0, res_12} + {1'b0, bit_5}))) begin
          cassiopeia = (n_9 - (res_12 + bit_5));
          n_11 = cassiopeia[63 : 0];
          carina = ((res_12 >> 64'h1) + bit_5);
          res_15 = carina[63 : 0];
        end else begin
          n_11 = n_9;
          res_15 = (res_12 >> 64'h1);
        end
        bit_6 = (bit_5 >> 64'h2);
        if (({1'b0, n_11} >= ({1'b0, res_15} + {1'b0, bit_6}))) begin
          vela = (n_11 - (res_15 + bit_6));
          n_13 = vela[63 : 0];
          auriga = ((res_15 >> 64'h1) + bit_6);
          res_18 = auriga[63 : 0];
        end else begin
          n_13 = n_11;
          res_18 = (res_15 >> 64'h1);
        end
        bit_7 = (bit_6 >> 64'h2);
        if (({1'b0, n_13} >= ({1'b0, res_18} + {1'b0, bit_7}))) begin
          cepheus = (n_13 - (res_18 + bit_7));
          n_15 = cepheus[63 : 0];
          columba = ((res_18 >> 64'h1) + bit_7);
          res_21 = columba[63 : 0];
        end else begin
          n_15 = n_13;
          res_21 = (res_18 >> 64'h1);
        end
        bit_8 = (bit_7 >> 64'h2);
        if (({1'b0, n_15} >= ({1'b0, res_21} + {1'b0, bit_8}))) begin
          corvus = (n_15 - (res_21 + bit_8));
          n_17 = corvus[63 : 0];
          crux = ((res_21 >> 64'h1) + bit_8);
          res_24 = crux[63 : 0];
        end else begin
          n_17 = n_15;
          res_24 = (res_21 >> 64'h1);
        end
        bit_9 = (bit_8 >> 64'h2);
        if (({1'b0, n_17} >= ({1'b0, res_24} + {1'b0, bit_9}))) begin
          fornax = (n_17 - (res_24 + bit_9));
          n_19 = fornax[63 : 0];
          gemini = ((res_24 >> 64'h1) + bit_9);
          res_27 = gemini[63 : 0];
        end else begin
          n_19 = n_17;
          res_27 = (res_24 >> 64'h1);
        end
        bit_10 = (bit_9 >> 64'h2);
        if (({1'b0, n_19} >= ({1'b0, res_27} + {1'b0, bit_10}))) begin
          hercules = (n_19 - (res_27 + bit_10));
          n_21 = hercules[63 : 0];
          indus = ((res_27 >> 64'h1) + bit_10);
          res_30 = indus[63 : 0];
        end else begin
          n_21 = n_19;
          res_30 = (res_27 >> 64'h1);
        end
        bit_11 = (bit_10 >> 64'h2);
        if (({1'b0, n_21} >= ({1'b0, res_30} + {1'b0, bit_11}))) begin
          lupus = (n_21 - (res_30 + bit_11));
          n_23 = lupus[63 : 0];
          lynx = ((res_30 >> 64'h1) + bit_11);
          res_33 = lynx[63 : 0];
        end else begin
          n_23 = n_21;
          res_33 = (res_30 >> 64'h1);
        end
        bit_12 = (bit_11 >> 64'h2);
        if (({1'b0, n_23} >= ({1'b0, res_33} + {1'b0, bit_12}))) begin
          norma = (n_23 - (res_33 + bit_12));
          n_25 = norma[63 : 0];
          octans = ((res_33 >> 64'h1) + bit_12);
          res_36 = octans[63 : 0];
        end else begin
          n_25 = n_23;
          res_36 = (res_33 >> 64'h1);
        end
        bit_13 = (bit_12 >> 64'h2);
        if (({1'b0, n_25} >= ({1'b0, res_36} + {1'b0, bit_13}))) begin
          pictor = (n_25 - (res_36 + bit_13));
          n_27 = pictor[63 : 0];
          pyxis = ((res_36 >> 64'h1) + bit_13);
          res_39 = pyxis[63 : 0];
        end else begin
          n_27 = n_25;
          res_39 = (res_36 >> 64'h1);
        end
        bit_14 = (bit_13 >> 64'h2);
        if (({1'b0, n_27} >= ({1'b0, res_39} + {1'b0, bit_14}))) begin
          sagitta = (n_27 - (res_39 + bit_14));
          n_29 = sagitta[63 : 0];
          serpens = ((res_39 >> 64'h1) + bit_14);
          res_42 = serpens[63 : 0];
        end else begin
          n_29 = n_27;
          res_42 = (res_39 >> 64'h1);
        end
        bit_15 = (bit_14 >> 64'h2);
        if (({1'b0, n_29} >= ({1'b0, res_42} + {1'b0, bit_15}))) begin
          tucana = (n_29 - (res_42 + bit_15));
          n_31 = tucana[63 : 0];
          volans = ((res_42 >> 64'h1) + bit_15);
          res_45 = volans[63 : 0];
        end else begin
          n_31 = n_29;
          res_45 = (res_42 >> 64'h1);
        end
        bit_16 = (bit_15 >> 64'h2);
        if (({1'b0, n_31} >= ({1'b0, res_45} + {1'b0, bit_16}))) begin
          vulpecula = (n_31 - (res_45 + bit_16));
          n_33 = vulpecula[63 : 0];
          orion_1 = ((res_45 >> 64'h1) + bit_16);
          res_48 = orion_1[63 : 0];
        end else begin
          n_33 = n_31;
          res_48 = (res_45 >> 64'h1);
        end
        bit_17 = (bit_16 >> 64'h2);
        if (({1'b0, n_33} >= ({1'b0, res_48} + {1'b0, bit_17}))) begin
          lyra_1 = (n_33 - (res_48 + bit_17));
          n_35 = lyra_1[63 : 0];
          cygnus_1 = ((res_48 >> 64'h1) + bit_17);
          res_51 = cygnus_1[63 : 0];
        end else begin
          n_35 = n_33;
          res_51 = (res_48 >> 64'h1);
        end
        bit_18 = (bit_17 >> 64'h2);
        if (({1'b0, n_35} >= ({1'b0, res_51} + {1'b0, bit_18}))) begin
          draco_1 = (n_35 - (res_51 + bit_18));
          n_37 = draco_1[63 : 0];
          aquila_1 = ((res_51 >> 64'h1) + bit_18);
          res_54 = aquila_1[63 : 0];
        end else begin
          n_37 = n_35;
          res_54 = (res_51 >> 64'h1);
        end
        bit_19 = (bit_18 >> 64'h2);
        if (({1'b0, n_37} >= ({1'b0, res_54} + {1'b0, bit_19}))) begin
          pegasus_1 = (n_37 - (res_54 + bit_19));
          n_39 = pegasus_1[63 : 0];
          perseus_1 = ((res_54 >> 64'h1) + bit_19);
          res_57 = perseus_1[63 : 0];
        end else begin
          n_39 = n_37;
          res_57 = (res_54 >> 64'h1);
        end
        bit_20 = (bit_19 >> 64'h2);
        if (({1'b0, n_39} >= ({1'b0, res_57} + {1'b0, bit_20}))) begin
          andromeda_1 = (n_39 - (res_57 + bit_20));
          n_41 = andromeda_1[63 : 0];
          phoenix_1 = ((res_57 >> 64'h1) + bit_20);
          res_60 = phoenix_1[63 : 0];
        end else begin
          n_41 = n_39;
          res_60 = (res_57 >> 64'h1);
        end
        bit_21 = (bit_20 >> 64'h2);
        if (({1'b0, n_41} >= ({1'b0, res_60} + {1'b0, bit_21}))) begin
          hydra_1 = (n_41 - (res_60 + bit_21));
          n_43 = hydra_1[63 : 0];
          centaurus_1 = ((res_60 >> 64'h1) + bit_21);
          res_63 = centaurus_1[63 : 0];
        end else begin
          n_43 = n_41;
          res_63 = (res_60 >> 64'h1);
        end
        bit_22 = (bit_21 >> 64'h2);
        if (({1'b0, n_43} >= ({1'b0, res_63} + {1'b0, bit_22}))) begin
          cassiopeia_1 = (n_43 - (res_63 + bit_22));
          n_45 = cassiopeia_1[63 : 0];
          carina_1 = ((res_63 >> 64'h1) + bit_22);
          res_66 = carina_1[63 : 0];
        end else begin
          n_45 = n_43;
          res_66 = (res_63 >> 64'h1);
        end
        bit_23 = (bit_22 >> 64'h2);
        if (({1'b0, n_45} >= ({1'b0, res_66} + {1'b0, bit_23}))) begin
          vela_1 = (n_45 - (res_66 + bit_23));
          n_47 = vela_1[63 : 0];
          auriga_1 = ((res_66 >> 64'h1) + bit_23);
          res_69 = auriga_1[63 : 0];
        end else begin
          n_47 = n_45;
          res_69 = (res_66 >> 64'h1);
        end
        bit_24 = (bit_23 >> 64'h2);
        if (({1'b0, n_47} >= ({1'b0, res_69} + {1'b0, bit_24}))) begin
          cepheus_1 = ((res_69 >> 64'h1) + bit_24);
          res_72 = cepheus_1[63 : 0];
        end else begin
          res_72 = (res_69 >> 64'h1);
        end
        result <= $signed(res_72[31 : 0]);
        result_valid <= 1'b1;
      end
    end
  end

endmodule //FixedSqrt
