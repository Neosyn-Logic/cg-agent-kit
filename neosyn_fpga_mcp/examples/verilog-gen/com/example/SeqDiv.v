
/**
 * Sequential divider: one stage/cycle, state persists, reads inputs only when idle,
 * writes result only when done. Tests whether Cg supports rate-changing port I/O.
 */
module SeqDiv(input clock, input reset_n, input signed [31 : 0] a, input a_valid, input signed [31 : 0] b, input b_valid, output reg signed [31 : 0] q, output reg q_valid);


  /**
   * State variables
   */
  reg [63 : 0] num;
  reg [63 : 0] rem;
  reg [63 : 0] quo;
  reg [63 : 0] dd;
  reg [5 : 0] step;
  reg  busy;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of SeqDiv
    if (~reset_n) begin
      num <= 64'h0;
      rem <= 64'h0;
      quo <= 64'h0;
      dd <= 64'h0;
      step <= 6'h0;
      busy <= 1'b0;
      q <= 32'b0;
      q_valid <= 1'b0;
    end else begin
      q_valid <= 1'b0;
      
      if (((a_valid && b_valid) && ! (busy))) begin : FSM_SeqDiv_a // line 11
        reg [79 : 0] orion;
      
        orion = {$unsigned($signed({{32{a[31]}}, a})), {(5'h10){1'b0}}};
        num <= orion[63 : 0];
        dd <= $unsigned($signed({{32{b[31]}}, b}));
        rem <= 64'h0;
        quo <= 64'h0;
        step <= 6'h0;
        busy <= 1'b1;
      end else if ((busy && (({1'b0, step} + 7'h1) == 7'h30))) begin : FSM_SeqDiv_b // line 14
        reg [63 : 0] rem_0_2;
        reg [63 : 0] quo_0_2;
        reg [63 : 0] rem_0_4;
        reg [63 : 0] quo_0_4;
        reg [64 : 0] lyra;
        reg [63 : 0] cygnus;
        reg [64 : 0] draco;
        reg [64 : 0] aquila;
        reg [64 : 0] pegasus;
        reg [64 : 0] perseus;
        reg [6 : 0] andromeda;
      
        lyra = {rem, {(1'h1){1'b0}}};
        cygnus = (num >> 64'h2f);
        draco = (lyra[63 : 0] | (cygnus[16 : 0] & 17'h1));
        rem_0_2 = draco[63 : 0];
        aquila = {quo, {(1'h1){1'b0}}};
        quo_0_2 = aquila[63 : 0];
        if ((rem_0_2 >= dd)) begin
          pegasus = (rem_0_2 - dd);
          rem_0_4 = pegasus[63 : 0];
          quo_0_4 = (quo_0_2 | 64'h1);
        end else begin
          rem_0_4 = rem_0_2;
          quo_0_4 = quo_0_2;
        end
        q <= $signed(quo_0_4[31 : 0]);
        q_valid <= 1'b1;
        busy <= 1'b0;
        rem <= rem_0_4;
        perseus = {num, {(1'h1){1'b0}}};
        num <= perseus[63 : 0];
        quo <= quo_0_4;
        andromeda = (step + 6'h1);
        step <= andromeda[5 : 0];
      end else if ((busy && ! ((({1'b0, step} + 7'h1) == 7'h30)))) begin : FSM_SeqDiv_c // line 14
        reg [63 : 0] rem_0_2;
        reg [63 : 0] quo_0_2;
        reg [63 : 0] rem_0_4;
        reg [63 : 0] quo_0_4;
        reg [64 : 0] phoenix;
        reg [63 : 0] hydra;
        reg [64 : 0] centaurus;
        reg [64 : 0] cassiopeia;
        reg [64 : 0] carina;
        reg [64 : 0] vela;
        reg [6 : 0] auriga;
      
        phoenix = {rem, {(1'h1){1'b0}}};
        hydra = (num >> 64'h2f);
        centaurus = (phoenix[63 : 0] | (hydra[16 : 0] & 17'h1));
        rem_0_2 = centaurus[63 : 0];
        cassiopeia = {quo, {(1'h1){1'b0}}};
        quo_0_2 = cassiopeia[63 : 0];
        if ((rem_0_2 >= dd)) begin
          carina = (rem_0_2 - dd);
          rem_0_4 = carina[63 : 0];
          quo_0_4 = (quo_0_2 | 64'h1);
        end else begin
          rem_0_4 = rem_0_2;
          quo_0_4 = quo_0_2;
        end
        rem <= rem_0_4;
        vela = {num, {(1'h1){1'b0}}};
        num <= vela[63 : 0];
        quo <= quo_0_4;
        auriga = (step + 6'h1);
        step <= auriga[5 : 0];
      end
    end
  end

endmodule //SeqDiv
