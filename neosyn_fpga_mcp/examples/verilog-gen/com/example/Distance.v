
/**
 * Euclidean distance sqrt(sum (a-b)^2), PORT-DRIVEN -> real datapath (MAC + isqrt).
 */
module Distance(input clock, input reset_n, input signed [31 : 0] a0, input a0_valid, input signed [31 : 0] a1, input a1_valid, input signed [31 : 0] a2, input a2_valid, input signed [31 : 0] a3, input a3_valid, input signed [31 : 0] b0, input b0_valid, input signed [31 : 0] b1, input b1_valid, input signed [31 : 0] b2, input b2_valid, input signed [31 : 0] b3, input b3_valid, output reg signed [31 : 0] result, output reg result_valid);


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
  always @(negedge reset_n or posedge clock) begin // body of Distance
    if (~reset_n) begin
      result <= 32'b0;
      result_valid <= 1'b0;
    end else begin
      result_valid <= 1'b0;
      
      if ((((((((a0_valid && b0_valid) && a1_valid) && b1_valid) && a2_valid) && b2_valid) && a3_valid) && b3_valid)) begin : FSM_Distance_a // line 9
        reg signed [31 : 0] d0_1;
        reg signed [31 : 0] d1_1;
        reg signed [31 : 0] d2_1;
        reg signed [31 : 0] d3_1;
        reg signed [31 : 0] fxmul_ret_1;
        reg signed [31 : 0] fxmul_ret_0_1;
        reg signed [31 : 0] fxmul_ret_1_1;
        reg signed [31 : 0] fxmul_ret_2_1;
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
        reg signed [32 : 0] draco;
        reg signed [32 : 0] aquila;
        reg signed [32 : 0] pegasus;
        reg signed [32 : 0] perseus;
        reg signed [32 : 0] andromeda;
        reg signed [33 : 0] phoenix;
        reg signed [34 : 0] hydra;
        reg [79 : 0] centaurus;
        reg [109 : 0] cassiopeia;
        reg [65 : 0] carina;
        reg [64 : 0] vela;
        reg [0 : 0] auriga;
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
        reg [65 : 0] cepheus_1;
        reg [64 : 0] columba_1;
        reg [65 : 0] corvus_1;
        reg [64 : 0] crux_1;
        reg [65 : 0] fornax_1;
        reg [64 : 0] gemini_1;
        reg [65 : 0] hercules_1;
        reg [64 : 0] indus_1;
        reg [65 : 0] lupus_1;
        reg [64 : 0] lynx_1;
        reg [64 : 0] norma_1;
      
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
        andromeda = ($signed({{1{fxmul_ret_1[31]}}, fxmul_ret_1}) + $signed({{1{fxmul_ret_0_1[31]}}, fxmul_ret_0_1}));
        phoenix = ($signed({{1{andromeda[32]}}, andromeda}) + $signed({{2{fxmul_ret_1_1[31]}}, fxmul_ret_1_1}));
        hydra = ($signed({{1{phoenix[33]}}, phoenix}) + $signed({{3{fxmul_ret_2_1[31]}}, fxmul_ret_2_1}));
        centaurus = {$unsigned($signed({{29{hydra[34]}}, hydra})), {(5'h10){1'b0}}};
        n_1 = centaurus[63 : 0];
        cassiopeia = {64'h1, {(6'h2e){1'b0}}};
        bit_1 = cassiopeia[63 : 0];
        if (({1'b0, n_1} >= (65'h0 + {1'b0, bit_1}))) begin
          carina = (n_1 - (64'h0 + bit_1));
          n_3 = carina[63 : 0];
          vela = ((1'h0 >> 1'h1) + bit_1);
          res_3 = vela[63 : 0];
        end else begin
          n_3 = n_1;
          auriga = (1'h0 >> 1'h1);
          res_3 = {63'b0, auriga};
        end
        bit_2 = (bit_1 >> 64'h2);
        if (({1'b0, n_3} >= ({1'b0, res_3} + {1'b0, bit_2}))) begin
          cepheus = (n_3 - (res_3 + bit_2));
          n_5 = cepheus[63 : 0];
          columba = ((res_3 >> 64'h1) + bit_2);
          res_6 = columba[63 : 0];
        end else begin
          n_5 = n_3;
          res_6 = (res_3 >> 64'h1);
        end
        bit_3 = (bit_2 >> 64'h2);
        if (({1'b0, n_5} >= ({1'b0, res_6} + {1'b0, bit_3}))) begin
          corvus = (n_5 - (res_6 + bit_3));
          n_7 = corvus[63 : 0];
          crux = ((res_6 >> 64'h1) + bit_3);
          res_9 = crux[63 : 0];
        end else begin
          n_7 = n_5;
          res_9 = (res_6 >> 64'h1);
        end
        bit_4 = (bit_3 >> 64'h2);
        if (({1'b0, n_7} >= ({1'b0, res_9} + {1'b0, bit_4}))) begin
          fornax = (n_7 - (res_9 + bit_4));
          n_9 = fornax[63 : 0];
          gemini = ((res_9 >> 64'h1) + bit_4);
          res_12 = gemini[63 : 0];
        end else begin
          n_9 = n_7;
          res_12 = (res_9 >> 64'h1);
        end
        bit_5 = (bit_4 >> 64'h2);
        if (({1'b0, n_9} >= ({1'b0, res_12} + {1'b0, bit_5}))) begin
          hercules = (n_9 - (res_12 + bit_5));
          n_11 = hercules[63 : 0];
          indus = ((res_12 >> 64'h1) + bit_5);
          res_15 = indus[63 : 0];
        end else begin
          n_11 = n_9;
          res_15 = (res_12 >> 64'h1);
        end
        bit_6 = (bit_5 >> 64'h2);
        if (({1'b0, n_11} >= ({1'b0, res_15} + {1'b0, bit_6}))) begin
          lupus = (n_11 - (res_15 + bit_6));
          n_13 = lupus[63 : 0];
          lynx = ((res_15 >> 64'h1) + bit_6);
          res_18 = lynx[63 : 0];
        end else begin
          n_13 = n_11;
          res_18 = (res_15 >> 64'h1);
        end
        bit_7 = (bit_6 >> 64'h2);
        if (({1'b0, n_13} >= ({1'b0, res_18} + {1'b0, bit_7}))) begin
          norma = (n_13 - (res_18 + bit_7));
          n_15 = norma[63 : 0];
          octans = ((res_18 >> 64'h1) + bit_7);
          res_21 = octans[63 : 0];
        end else begin
          n_15 = n_13;
          res_21 = (res_18 >> 64'h1);
        end
        bit_8 = (bit_7 >> 64'h2);
        if (({1'b0, n_15} >= ({1'b0, res_21} + {1'b0, bit_8}))) begin
          pictor = (n_15 - (res_21 + bit_8));
          n_17 = pictor[63 : 0];
          pyxis = ((res_21 >> 64'h1) + bit_8);
          res_24 = pyxis[63 : 0];
        end else begin
          n_17 = n_15;
          res_24 = (res_21 >> 64'h1);
        end
        bit_9 = (bit_8 >> 64'h2);
        if (({1'b0, n_17} >= ({1'b0, res_24} + {1'b0, bit_9}))) begin
          sagitta = (n_17 - (res_24 + bit_9));
          n_19 = sagitta[63 : 0];
          serpens = ((res_24 >> 64'h1) + bit_9);
          res_27 = serpens[63 : 0];
        end else begin
          n_19 = n_17;
          res_27 = (res_24 >> 64'h1);
        end
        bit_10 = (bit_9 >> 64'h2);
        if (({1'b0, n_19} >= ({1'b0, res_27} + {1'b0, bit_10}))) begin
          tucana = (n_19 - (res_27 + bit_10));
          n_21 = tucana[63 : 0];
          volans = ((res_27 >> 64'h1) + bit_10);
          res_30 = volans[63 : 0];
        end else begin
          n_21 = n_19;
          res_30 = (res_27 >> 64'h1);
        end
        bit_11 = (bit_10 >> 64'h2);
        if (({1'b0, n_21} >= ({1'b0, res_30} + {1'b0, bit_11}))) begin
          vulpecula = (n_21 - (res_30 + bit_11));
          n_23 = vulpecula[63 : 0];
          orion_1 = ((res_30 >> 64'h1) + bit_11);
          res_33 = orion_1[63 : 0];
        end else begin
          n_23 = n_21;
          res_33 = (res_30 >> 64'h1);
        end
        bit_12 = (bit_11 >> 64'h2);
        if (({1'b0, n_23} >= ({1'b0, res_33} + {1'b0, bit_12}))) begin
          lyra_1 = (n_23 - (res_33 + bit_12));
          n_25 = lyra_1[63 : 0];
          cygnus_1 = ((res_33 >> 64'h1) + bit_12);
          res_36 = cygnus_1[63 : 0];
        end else begin
          n_25 = n_23;
          res_36 = (res_33 >> 64'h1);
        end
        bit_13 = (bit_12 >> 64'h2);
        if (({1'b0, n_25} >= ({1'b0, res_36} + {1'b0, bit_13}))) begin
          draco_1 = (n_25 - (res_36 + bit_13));
          n_27 = draco_1[63 : 0];
          aquila_1 = ((res_36 >> 64'h1) + bit_13);
          res_39 = aquila_1[63 : 0];
        end else begin
          n_27 = n_25;
          res_39 = (res_36 >> 64'h1);
        end
        bit_14 = (bit_13 >> 64'h2);
        if (({1'b0, n_27} >= ({1'b0, res_39} + {1'b0, bit_14}))) begin
          pegasus_1 = (n_27 - (res_39 + bit_14));
          n_29 = pegasus_1[63 : 0];
          perseus_1 = ((res_39 >> 64'h1) + bit_14);
          res_42 = perseus_1[63 : 0];
        end else begin
          n_29 = n_27;
          res_42 = (res_39 >> 64'h1);
        end
        bit_15 = (bit_14 >> 64'h2);
        if (({1'b0, n_29} >= ({1'b0, res_42} + {1'b0, bit_15}))) begin
          andromeda_1 = (n_29 - (res_42 + bit_15));
          n_31 = andromeda_1[63 : 0];
          phoenix_1 = ((res_42 >> 64'h1) + bit_15);
          res_45 = phoenix_1[63 : 0];
        end else begin
          n_31 = n_29;
          res_45 = (res_42 >> 64'h1);
        end
        bit_16 = (bit_15 >> 64'h2);
        if (({1'b0, n_31} >= ({1'b0, res_45} + {1'b0, bit_16}))) begin
          hydra_1 = (n_31 - (res_45 + bit_16));
          n_33 = hydra_1[63 : 0];
          centaurus_1 = ((res_45 >> 64'h1) + bit_16);
          res_48 = centaurus_1[63 : 0];
        end else begin
          n_33 = n_31;
          res_48 = (res_45 >> 64'h1);
        end
        bit_17 = (bit_16 >> 64'h2);
        if (({1'b0, n_33} >= ({1'b0, res_48} + {1'b0, bit_17}))) begin
          cassiopeia_1 = (n_33 - (res_48 + bit_17));
          n_35 = cassiopeia_1[63 : 0];
          carina_1 = ((res_48 >> 64'h1) + bit_17);
          res_51 = carina_1[63 : 0];
        end else begin
          n_35 = n_33;
          res_51 = (res_48 >> 64'h1);
        end
        bit_18 = (bit_17 >> 64'h2);
        if (({1'b0, n_35} >= ({1'b0, res_51} + {1'b0, bit_18}))) begin
          vela_1 = (n_35 - (res_51 + bit_18));
          n_37 = vela_1[63 : 0];
          auriga_1 = ((res_51 >> 64'h1) + bit_18);
          res_54 = auriga_1[63 : 0];
        end else begin
          n_37 = n_35;
          res_54 = (res_51 >> 64'h1);
        end
        bit_19 = (bit_18 >> 64'h2);
        if (({1'b0, n_37} >= ({1'b0, res_54} + {1'b0, bit_19}))) begin
          cepheus_1 = (n_37 - (res_54 + bit_19));
          n_39 = cepheus_1[63 : 0];
          columba_1 = ((res_54 >> 64'h1) + bit_19);
          res_57 = columba_1[63 : 0];
        end else begin
          n_39 = n_37;
          res_57 = (res_54 >> 64'h1);
        end
        bit_20 = (bit_19 >> 64'h2);
        if (({1'b0, n_39} >= ({1'b0, res_57} + {1'b0, bit_20}))) begin
          corvus_1 = (n_39 - (res_57 + bit_20));
          n_41 = corvus_1[63 : 0];
          crux_1 = ((res_57 >> 64'h1) + bit_20);
          res_60 = crux_1[63 : 0];
        end else begin
          n_41 = n_39;
          res_60 = (res_57 >> 64'h1);
        end
        bit_21 = (bit_20 >> 64'h2);
        if (({1'b0, n_41} >= ({1'b0, res_60} + {1'b0, bit_21}))) begin
          fornax_1 = (n_41 - (res_60 + bit_21));
          n_43 = fornax_1[63 : 0];
          gemini_1 = ((res_60 >> 64'h1) + bit_21);
          res_63 = gemini_1[63 : 0];
        end else begin
          n_43 = n_41;
          res_63 = (res_60 >> 64'h1);
        end
        bit_22 = (bit_21 >> 64'h2);
        if (({1'b0, n_43} >= ({1'b0, res_63} + {1'b0, bit_22}))) begin
          hercules_1 = (n_43 - (res_63 + bit_22));
          n_45 = hercules_1[63 : 0];
          indus_1 = ((res_63 >> 64'h1) + bit_22);
          res_66 = indus_1[63 : 0];
        end else begin
          n_45 = n_43;
          res_66 = (res_63 >> 64'h1);
        end
        bit_23 = (bit_22 >> 64'h2);
        if (({1'b0, n_45} >= ({1'b0, res_66} + {1'b0, bit_23}))) begin
          lupus_1 = (n_45 - (res_66 + bit_23));
          n_47 = lupus_1[63 : 0];
          lynx_1 = ((res_66 >> 64'h1) + bit_23);
          res_69 = lynx_1[63 : 0];
        end else begin
          n_47 = n_45;
          res_69 = (res_66 >> 64'h1);
        end
        bit_24 = (bit_23 >> 64'h2);
        if (({1'b0, n_47} >= ({1'b0, res_69} + {1'b0, bit_24}))) begin
          norma_1 = ((res_69 >> 64'h1) + bit_24);
          res_72 = norma_1[63 : 0];
        end else begin
          res_72 = (res_69 >> 64'h1);
        end
        result <= $signed(res_72[31 : 0]);
        result_valid <= 1'b1;
      end
    end
  end

endmodule //Distance
