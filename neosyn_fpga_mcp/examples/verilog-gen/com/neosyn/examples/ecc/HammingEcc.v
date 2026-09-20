
/**
 * Hamming SECDED — Single Error Correct, Double Error Detect. The error
 * correction in every ECC memory, every NAND controller, every register file that
 * has to survive a single-event upset, and every link too slow to retransmit.
 * 
 * Encoder AND decoder in one block, with an ERROR-INJECTION port between them,
 * so the whole claim is testable in a plain vector fixture: `code` is the clean
 * codeword the encoder produced, `err` is a bit mask XORed into it (the "channel"
 * — 0x04 means bit 2 got flipped in transit), and `dout`/`corrected`/`dblerr` are
 * what the decoder makes of the damaged word. In a real design the two halves sit
 * at opposite ends of a memory or a wire and `err` is whatever the universe does.
 * 
 * ---- THE CODE: extended Hamming(7,4), i.e. (8,4) ----
 * Bit POSITIONS are 1-based here because that is what makes the construction
 * work; the wire index is position - 1.
 * pos 1 = p1   pos 2 = p2   pos 3 = d1   pos 4 = p4
 * pos 5 = d2   pos 6 = d3   pos 7 = d4   pos 8 = p8 (overall parity)
 * Parity bits live at the POWER-OF-TWO positions, and each covers exactly the
 * positions whose index has its bit set:
 * p1 covers 1,3,5,7    p2 covers 2,3,6,7    p4 covers 4,5,6,7
 * THAT is the trick, and it is worth understanding rather than memorising: recompute
 * the three parities over the RECEIVED word and the three results, read as a
 * binary number, ARE the position of the flipped bit. 0 means no error. There is
 * no lookup table and no search — the syndrome points straight at the damage.
 * 
 * Hamming(7,4) alone has minimum distance 3: it corrects one error, but a DOUBLE
 * error lands on some other valid codeword's correction and it silently
 * "corrects" you to the wrong data. Adding p8, a parity over all seven other
 * bits, lifts the distance to 4 and separates the two cases:
 * p8 fails, syndrome != 0  -> ONE error, at position `syn`. Fix it.
 * p8 fails, syndrome == 0  -> the error is in p8 itself. Fix that.
 * p8 holds, syndrome != 0  -> TWO errors. Detected, NOT correctable.
 * p8 holds, syndrome == 0  -> clean (or four errors — no code is free).
 * The `dblerr` line is the entire value of the "DED" half: it converts a silent
 * wrong answer into a loud one, which is what lets a memory controller raise a
 * machine check instead of handing bad data to software.
 * 
 * `dout` IS MEANINGLESS WHEN `dblerr` IS HIGH. There is no correct answer to
 * return — the block emits whatever the (wrong) syndrome pointed at. Look at the
 * test: vector 18 asks for 0xB and gets 0xE. That is not a bug, that is what
 * "detect but do not correct" means, and it is why the flag must be wired.
 * 
 * ---- WHAT THE TEST PROVES ----
 * * vectors 1-8: EVERY ONE of the eight single-bit error positions, injected
 * one at a time into the codeword for 0xB, is corrected back to 0xB with
 * `corrected` high — including vector 8, where the damaged bit is the parity
 * bit p8 itself (syndrome 0, which the naive decoder mishandles).
 * * vectors 11-13, 18-21: seven different DOUBLE-bit errors, on two different
 * data words, all raise `dblerr` and all leave `corrected` low.
 * * vectors 0, 9, 14-17: clean codewords for 0x0, 0x5, 0x6, 0x9, 0xB, 0xF pass
 * through with both flags low.
 * Every number came from a Python model of exactly this arithmetic, which was
 * first checked EXHAUSTIVELY: all 16 data words x (1 clean + 8 single-bit + 28
 * double-bit error patterns) = 592 cases behave as claimed. The 22 vectors here
 * are the readable subset of that.
 * 
 * TO ADAPT:
 * * (72,64) SECDED, the DRAM/cache standard — same construction, 8 parity bits
 * (7 Hamming + 1 overall) over 64 data bits. The parity equations become
 * 64-input XOR trees; generate them from the position masks rather than
 * writing them out.
 * * DETECT-ONLY — drop the correction mux and keep the syndrome compare. Much
 * smaller, and correct when you can retransmit.
 * * SEC only (no p8) — drop the overall parity. Do this only if a double error
 * is genuinely impossible; otherwise you have built a machine that
 * confidently corrupts data.
 * * BURST errors (adjacent bits, the usual failure of a wire or a DRAM column)
 * — Hamming is the wrong tool; INTERLEAVE several codewords so a burst hits
 * one bit of each, or use Reed-Solomon.
 * * pure DETECTION over a long message — use Crc8/CRC-32 instead. A CRC detects
 * far more than it can locate; Hamming locates one bit and that is all.
 * 
 * This is combinational: no registers, one answer per cycle, no latency. In a
 * memory path the encoder sits before the write and the decoder after the read,
 * and the syndrome logic is usually the critical path — pipeline it (a register
 * between syndrome and correction) if it does not meet timing.
 */
module HammingEcc(input clock, input reset_n, input [3 : 0] din, input din_valid, input [7 : 0] err, input err_valid, output reg [7 : 0] code, output reg code_valid, output reg [3 : 0] dout, output reg dout_valid, output reg  corrected, output reg corrected_valid, output reg  dblerr, output reg dblerr_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of HammingEcc
    if (~reset_n) begin
      code <= 8'b0;
      dout <= 4'b0;
      corrected <= 1'b0;
      dblerr <= 1'b0;
      code_valid <= 1'b0;
      dout_valid <= 1'b0;
      corrected_valid <= 1'b0;
      dblerr_valid <= 1'b0;
    end else begin
      code_valid <= 1'b0;
      dout_valid <= 1'b0;
      corrected_valid <= 1'b0;
      dblerr_valid <= 1'b0;
      
      if ((din_valid && err_valid)) begin : FSM_HammingEcc_a // line 105
        reg  d1_1;
        reg  d2_1;
        reg  d3_1;
        reg  d4_1;
        reg  p1_1;
        reg  p2_1;
        reg  p4_1;
        reg [0 : 0] tmp_if_2;
        reg [0 : 0] tmp_if_0_2;
        reg [0 : 0] tmp_if_1_2;
        reg [0 : 0] tmp_if_2_2;
        reg [0 : 0] tmp_if_3_2;
        reg [0 : 0] tmp_if_4_2;
        reg [0 : 0] tmp_if_5_2;
        reg [0 : 0] tmp_if_6_2;
        reg  r1_1;
        reg  r2_1;
        reg  r3_1;
        reg  r4_1;
        reg  r5_1;
        reg  r6_1;
        reg  r7_1;
        reg [0 : 0] tmp_if_7_2;
        reg [0 : 0] tmp_if_8_2;
        reg [0 : 0] tmp_if_9_2;
        reg  cor_3;
        reg [7 : 0] fixed_3;
        reg [7 : 0] fixed_5;
        reg [7 : 0] fixed_7;
        reg [7 : 0] fixed_9;
        reg [7 : 0] fixed_11;
        reg [7 : 0] fixed_13;
        reg [7 : 0] fixed_15;
        reg [7 : 0] fixed_17;
        reg  dbl_3;
        reg  dbl_4;
        reg [0 : 0] tmp_if_10_2;
        reg [0 : 0] tmp_if_11_2;
        reg [0 : 0] tmp_if_12_2;
        reg [0 : 0] tmp_if_13_2;
        reg [3 : 0] orion;
        reg [3 : 0] lyra;
        reg [1 : 0] cygnus;
        reg [2 : 0] draco;
        reg [3 : 0] aquila;
        reg [4 : 0] pegasus;
        reg [5 : 0] perseus;
        reg [6 : 0] andromeda;
        reg [1 : 0] phoenix;
        reg [2 : 0] hydra;
        reg [3 : 0] centaurus;
        reg [4 : 0] cassiopeia;
        reg [5 : 0] carina;
        reg [6 : 0] vela;
        reg [7 : 0] auriga;
        reg [7 : 0] cepheus;
        reg [2 : 0] columba;
        reg [3 : 0] corvus;
        reg [4 : 0] crux;
        reg [5 : 0] fornax;
        reg [6 : 0] gemini;
        reg [7 : 0] hercules;
        reg [7 : 0] indus;
        reg [1 : 0] lupus;
        reg [3 : 0] lynx;
        reg [4 : 0] norma;
        reg [5 : 0] octans;
        reg [6 : 0] pictor;
        reg [7 : 0] pyxis;
        reg [7 : 0] sagitta;
        reg [1 : 0] serpens;
        reg [2 : 0] tucana;
        reg [4 : 0] volans;
        reg [5 : 0] vulpecula;
        reg [6 : 0] orion_1;
        reg [7 : 0] lyra_1;
        reg [7 : 0] cygnus_1;
        reg [1 : 0] draco_1;
        reg [2 : 0] aquila_1;
        reg [3 : 0] pegasus_1;
        reg [5 : 0] perseus_1;
        reg [6 : 0] andromeda_1;
        reg [7 : 0] phoenix_1;
        reg [7 : 0] hydra_1;
        reg [1 : 0] centaurus_1;
        reg [2 : 0] cassiopeia_1;
        reg [3 : 0] carina_1;
        reg [4 : 0] vela_1;
        reg [6 : 0] auriga_1;
        reg [7 : 0] cepheus_1;
        reg [7 : 0] columba_1;
        reg [1 : 0] corvus_1;
        reg [2 : 0] crux_1;
        reg [3 : 0] fornax_1;
        reg [4 : 0] gemini_1;
        reg [5 : 0] hercules_1;
        reg [7 : 0] indus_1;
        reg [7 : 0] lupus_1;
        reg [1 : 0] lynx_1;
        reg [2 : 0] norma_1;
        reg [3 : 0] octans_1;
        reg [4 : 0] pictor_1;
        reg [5 : 0] pyxis_1;
        reg [6 : 0] sagitta_1;
        reg [1 : 0] serpens_1;
        reg [1 : 0] tucana_1;
        reg [2 : 0] volans_1;
        reg [3 : 0] vulpecula_1;
        reg [4 : 0] orion_2;
        reg [5 : 0] lyra_2;
        reg [6 : 0] cygnus_2;
        reg [1 : 0] draco_2;
        reg [1 : 0] aquila_2;
        reg [2 : 0] pegasus_2;
        reg [3 : 0] perseus_2;
        reg [4 : 0] andromeda_2;
        reg [5 : 0] phoenix_2;
        reg [6 : 0] hydra_2;
        reg [1 : 0] centaurus_2;
        reg [1 : 0] cassiopeia_2;
        reg [2 : 0] carina_2;
        reg [3 : 0] vela_2;
        reg [4 : 0] auriga_2;
        reg [5 : 0] cepheus_2;
        reg [6 : 0] columba_2;
        reg [1 : 0] corvus_2;
        reg [1 : 0] crux_2;
        reg [2 : 0] fornax_2;
        reg [3 : 0] gemini_2;
        reg [4 : 0] hercules_2;
        reg [5 : 0] indus_2;
        reg [6 : 0] lupus_2;
        reg [1 : 0] lynx_2;
        reg [1 : 0] norma_2;
        reg [2 : 0] octans_2;
        reg [3 : 0] pictor_2;
        reg [4 : 0] pyxis_2;
        reg [5 : 0] sagitta_2;
        reg [6 : 0] serpens_2;
        reg [1 : 0] tucana_2;
        reg [1 : 0] volans_2;
        reg [2 : 0] vulpecula_2;
        reg [3 : 0] orion_3;
        reg [4 : 0] lyra_3;
        reg [5 : 0] cygnus_3;
        reg [6 : 0] draco_3;
        reg [1 : 0] aquila_3;
        reg [1 : 0] pegasus_3;
        reg [2 : 0] perseus_3;
        reg [3 : 0] andromeda_3;
        reg [4 : 0] phoenix_3;
        reg [5 : 0] hydra_3;
        reg [6 : 0] centaurus_3;
        reg [1 : 0] cassiopeia_3;
        reg [2 : 0] carina_3;
        reg [3 : 0] vela_3;
        reg [4 : 0] auriga_3;
        reg [5 : 0] cepheus_3;
        reg [6 : 0] columba_3;
        reg [1 : 0] corvus_3;
        reg [1 : 0] crux_3;
        reg [2 : 0] fornax_3;
        reg [3 : 0] gemini_3;
        reg [4 : 0] hercules_3;
        reg [5 : 0] indus_3;
        reg [6 : 0] lupus_3;
        reg [7 : 0] lynx_3;
        reg [7 : 0] norma_3;
        reg [7 : 0] octans_3;
        reg [7 : 0] pictor_3;
        reg [1 : 0] pyxis_3;
        reg [2 : 0] sagitta_3;
      
        d1_1 = (din[0 : 0] != 1'h0);
        orion = (din & 2'h2);
        d2_1 = (orion[1 : 0] != 2'h0);
        lyra = (din & 3'h4);
        d3_1 = (lyra[2 : 0] != 3'h0);
        d4_1 = ((din & 4'h8) != 4'h0);
        p1_1 = ((d1_1 ^ d2_1) ^ d4_1);
        p2_1 = ((d1_1 ^ d3_1) ^ d4_1);
        p4_1 = ((d2_1 ^ d3_1) ^ d4_1);
        // parity over all seven
        // Packing bools into a word: a bool does NOT cast to an integer type in
        // Cg ((u8) someBool is a type error), so select 1 or 0 with `? :`.
        if (p1_1) begin
          tmp_if_2 = 1'h1;
        end else begin
          tmp_if_2 = 1'h0;
        end
        if (p2_1) begin
          tmp_if_0_2 = 1'h1;
        end else begin
          tmp_if_0_2 = 1'h0;
        end
        if (d1_1) begin
          tmp_if_1_2 = 1'h1;
        end else begin
          tmp_if_1_2 = 1'h0;
        end
        if (p4_1) begin
          tmp_if_2_2 = 1'h1;
        end else begin
          tmp_if_2_2 = 1'h0;
        end
        if (d2_1) begin
          tmp_if_3_2 = 1'h1;
        end else begin
          tmp_if_3_2 = 1'h0;
        end
        if (d3_1) begin
          tmp_if_4_2 = 1'h1;
        end else begin
          tmp_if_4_2 = 1'h0;
        end
        if (d4_1) begin
          tmp_if_5_2 = 1'h1;
        end else begin
          tmp_if_5_2 = 1'h0;
        end
        if (((((((p1_1 ^ p2_1) ^ d1_1) ^ p4_1) ^ d2_1) ^ d3_1) ^ d4_1)) begin
          tmp_if_6_2 = 1'h1;
        end else begin
          tmp_if_6_2 = 1'h0;
        end
        cygnus = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
        draco = ({1'b0, cygnus} | {tmp_if_1_2, {(2'h2){1'b0}}});
        aquila = ({1'b0, draco} | {tmp_if_2_2, {(2'h3){1'b0}}});
        pegasus = ({1'b0, aquila} | {tmp_if_3_2, {(3'h4){1'b0}}});
        perseus = ({1'b0, pegasus} | {tmp_if_4_2, {(3'h5){1'b0}}});
        andromeda = ({1'b0, perseus} | {tmp_if_5_2, {(3'h6){1'b0}}});
        code <= ({1'b0, andromeda} | {tmp_if_6_2, {(3'h7){1'b0}}});
        code_valid <= 1'b1;
        phoenix = {tmp_if_0_2, {(1'h1){1'b0}}};
        hydra = {tmp_if_1_2, {(2'h2){1'b0}}};
        centaurus = {tmp_if_2_2, {(2'h3){1'b0}}};
        cassiopeia = {tmp_if_3_2, {(3'h4){1'b0}}};
        carina = {tmp_if_4_2, {(3'h5){1'b0}}};
        vela = {tmp_if_5_2, {(3'h6){1'b0}}};
        auriga = {tmp_if_6_2, {(3'h7){1'b0}}};
        cepheus = ((((((((tmp_if_2 | phoenix[0 : 0]) | hydra[0 : 0]) | centaurus[0 : 0]) | cassiopeia[0 : 0]) | carina[0 : 0]) | vela[0 : 0]) | auriga[0 : 0]) ^ err);
        r1_1 = (cepheus[0 : 0] != 1'h0);
        columba = {tmp_if_1_2, {(2'h2){1'b0}}};
        corvus = {tmp_if_2_2, {(2'h3){1'b0}}};
        crux = {tmp_if_3_2, {(3'h4){1'b0}}};
        fornax = {tmp_if_4_2, {(3'h5){1'b0}}};
        gemini = {tmp_if_5_2, {(3'h6){1'b0}}};
        hercules = {tmp_if_6_2, {(3'h7){1'b0}}};
        indus = ((((((((({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}}) | columba[1 : 0]) | corvus[1 : 0]) | crux[1 : 0]) | fornax[1 : 0]) | gemini[1 : 0]) | hercules[1 : 0]) ^ err) & 2'h2);
        r2_1 = (indus[1 : 0] != 2'h0);
        lupus = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
        lynx = {tmp_if_2_2, {(2'h3){1'b0}}};
        norma = {tmp_if_3_2, {(3'h4){1'b0}}};
        octans = {tmp_if_4_2, {(3'h5){1'b0}}};
        pictor = {tmp_if_5_2, {(3'h6){1'b0}}};
        pyxis = {tmp_if_6_2, {(3'h7){1'b0}}};
        sagitta = (((((((({1'b0, lupus} | {tmp_if_1_2, {(2'h2){1'b0}}}) | lynx[2 : 0]) | norma[2 : 0]) | octans[2 : 0]) | pictor[2 : 0]) | pyxis[2 : 0]) ^ err) & 3'h4);
        r3_1 = (sagitta[2 : 0] != 3'h0);
        serpens = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
        tucana = ({1'b0, serpens} | {tmp_if_1_2, {(2'h2){1'b0}}});
        volans = {tmp_if_3_2, {(3'h4){1'b0}}};
        vulpecula = {tmp_if_4_2, {(3'h5){1'b0}}};
        orion_1 = {tmp_if_5_2, {(3'h6){1'b0}}};
        lyra_1 = {tmp_if_6_2, {(3'h7){1'b0}}};
        cygnus_1 = ((((((({1'b0, tucana} | {tmp_if_2_2, {(2'h3){1'b0}}}) | volans[3 : 0]) | vulpecula[3 : 0]) | orion_1[3 : 0]) | lyra_1[3 : 0]) ^ err) & 4'h8);
        r4_1 = (cygnus_1[3 : 0] != 4'h0);
        draco_1 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
        aquila_1 = ({1'b0, draco_1} | {tmp_if_1_2, {(2'h2){1'b0}}});
        pegasus_1 = ({1'b0, aquila_1} | {tmp_if_2_2, {(2'h3){1'b0}}});
        perseus_1 = {tmp_if_4_2, {(3'h5){1'b0}}};
        andromeda_1 = {tmp_if_5_2, {(3'h6){1'b0}}};
        phoenix_1 = {tmp_if_6_2, {(3'h7){1'b0}}};
        hydra_1 = (((((({1'b0, pegasus_1} | {tmp_if_3_2, {(3'h4){1'b0}}}) | perseus_1[4 : 0]) | andromeda_1[4 : 0]) | phoenix_1[4 : 0]) ^ err) & 5'h10);
        r5_1 = (hydra_1[4 : 0] != 5'h0);
        centaurus_1 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
        cassiopeia_1 = ({1'b0, centaurus_1} | {tmp_if_1_2, {(2'h2){1'b0}}});
        carina_1 = ({1'b0, cassiopeia_1} | {tmp_if_2_2, {(2'h3){1'b0}}});
        vela_1 = ({1'b0, carina_1} | {tmp_if_3_2, {(3'h4){1'b0}}});
        auriga_1 = {tmp_if_5_2, {(3'h6){1'b0}}};
        cepheus_1 = {tmp_if_6_2, {(3'h7){1'b0}}};
        columba_1 = ((((({1'b0, vela_1} | {tmp_if_4_2, {(3'h5){1'b0}}}) | auriga_1[5 : 0]) | cepheus_1[5 : 0]) ^ err) & 6'h20);
        r6_1 = (columba_1[5 : 0] != 6'h0);
        corvus_1 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
        crux_1 = ({1'b0, corvus_1} | {tmp_if_1_2, {(2'h2){1'b0}}});
        fornax_1 = ({1'b0, crux_1} | {tmp_if_2_2, {(2'h3){1'b0}}});
        gemini_1 = ({1'b0, fornax_1} | {tmp_if_3_2, {(3'h4){1'b0}}});
        hercules_1 = ({1'b0, gemini_1} | {tmp_if_4_2, {(3'h5){1'b0}}});
        indus_1 = {tmp_if_6_2, {(3'h7){1'b0}}};
        lupus_1 = (((({1'b0, hercules_1} | {tmp_if_5_2, {(3'h6){1'b0}}}) | indus_1[6 : 0]) ^ err) & 7'h40);
        r7_1 = (lupus_1[6 : 0] != 7'h0);
        // what makes syn a POSITION
        // read as a binary number, the three checks ARE the 1-based bit position
        if ((((r1_1 ^ r3_1) ^ r5_1) ^ r7_1)) begin
          tmp_if_7_2 = 1'h1;
        end else begin
          tmp_if_7_2 = 1'h0;
        end
        // what makes syn a POSITION
        // read as a binary number, the three checks ARE the 1-based bit position
        if ((((r2_1 ^ r3_1) ^ r6_1) ^ r7_1)) begin
          tmp_if_8_2 = 1'h1;
        end else begin
          tmp_if_8_2 = 1'h0;
        end
        // what makes syn a POSITION
        // read as a binary number, the three checks ARE the 1-based bit position
        if ((((r4_1 ^ r5_1) ^ r6_1) ^ r7_1)) begin
          tmp_if_9_2 = 1'h1;
        end else begin
          tmp_if_9_2 = 1'h0;
        end
        lynx_1 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
        norma_1 = ({1'b0, lynx_1} | {tmp_if_1_2, {(2'h2){1'b0}}});
        octans_1 = ({1'b0, norma_1} | {tmp_if_2_2, {(2'h3){1'b0}}});
        pictor_1 = ({1'b0, octans_1} | {tmp_if_3_2, {(3'h4){1'b0}}});
        pyxis_1 = ({1'b0, pictor_1} | {tmp_if_4_2, {(3'h5){1'b0}}});
        sagitta_1 = ({1'b0, pyxis_1} | {tmp_if_5_2, {(3'h6){1'b0}}});
        if ((((((((r1_1 ^ r2_1) ^ r3_1) ^ r4_1) ^ r5_1) ^ r6_1) ^ r7_1) ^ (((({1'b0, sagitta_1} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err) & 8'h80) != 8'h0))) begin
          serpens_1 = ({1'b0, tmp_if_7_2} | {tmp_if_8_2, {(1'h1){1'b0}}});
          if ((({1'b0, serpens_1} | {tmp_if_9_2, {(2'h2){1'b0}}}) == 3'h1)) begin
            tucana_1 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
            volans_1 = ({1'b0, tucana_1} | {tmp_if_1_2, {(2'h2){1'b0}}});
            vulpecula_1 = ({1'b0, volans_1} | {tmp_if_2_2, {(2'h3){1'b0}}});
            orion_2 = ({1'b0, vulpecula_1} | {tmp_if_3_2, {(3'h4){1'b0}}});
            lyra_2 = ({1'b0, orion_2} | {tmp_if_4_2, {(3'h5){1'b0}}});
            cygnus_2 = ({1'b0, lyra_2} | {tmp_if_5_2, {(3'h6){1'b0}}});
            fixed_3 = ((({1'b0, cygnus_2} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err) ^ 8'h1);
          end else begin
            draco_2 = ({1'b0, tmp_if_7_2} | {tmp_if_8_2, {(1'h1){1'b0}}});
            if ((({1'b0, draco_2} | {tmp_if_9_2, {(2'h2){1'b0}}}) == 3'h2)) begin
              aquila_2 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
              pegasus_2 = ({1'b0, aquila_2} | {tmp_if_1_2, {(2'h2){1'b0}}});
              perseus_2 = ({1'b0, pegasus_2} | {tmp_if_2_2, {(2'h3){1'b0}}});
              andromeda_2 = ({1'b0, perseus_2} | {tmp_if_3_2, {(3'h4){1'b0}}});
              phoenix_2 = ({1'b0, andromeda_2} | {tmp_if_4_2, {(3'h5){1'b0}}});
              hydra_2 = ({1'b0, phoenix_2} | {tmp_if_5_2, {(3'h6){1'b0}}});
              fixed_5 = ((({1'b0, hydra_2} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err) ^ 8'h2);
            end else begin
              centaurus_2 = ({1'b0, tmp_if_7_2} | {tmp_if_8_2, {(1'h1){1'b0}}});
              if ((({1'b0, centaurus_2} | {tmp_if_9_2, {(2'h2){1'b0}}}) == 3'h3)) begin
                cassiopeia_2 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
                carina_2 = ({1'b0, cassiopeia_2} | {tmp_if_1_2, {(2'h2){1'b0}}});
                vela_2 = ({1'b0, carina_2} | {tmp_if_2_2, {(2'h3){1'b0}}});
                auriga_2 = ({1'b0, vela_2} | {tmp_if_3_2, {(3'h4){1'b0}}});
                cepheus_2 = ({1'b0, auriga_2} | {tmp_if_4_2, {(3'h5){1'b0}}});
                columba_2 = ({1'b0, cepheus_2} | {tmp_if_5_2, {(3'h6){1'b0}}});
                fixed_7 = ((({1'b0, columba_2} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err) ^ 8'h4);
              end else begin
                corvus_2 = ({1'b0, tmp_if_7_2} | {tmp_if_8_2, {(1'h1){1'b0}}});
                if ((({1'b0, corvus_2} | {tmp_if_9_2, {(2'h2){1'b0}}}) == 3'h4)) begin
                  crux_2 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
                  fornax_2 = ({1'b0, crux_2} | {tmp_if_1_2, {(2'h2){1'b0}}});
                  gemini_2 = ({1'b0, fornax_2} | {tmp_if_2_2, {(2'h3){1'b0}}});
                  hercules_2 = ({1'b0, gemini_2} | {tmp_if_3_2, {(3'h4){1'b0}}});
                  indus_2 = ({1'b0, hercules_2} | {tmp_if_4_2, {(3'h5){1'b0}}});
                  lupus_2 = ({1'b0, indus_2} | {tmp_if_5_2, {(3'h6){1'b0}}});
                  fixed_9 = ((({1'b0, lupus_2} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err) ^ 8'h8);
                end else begin
                  lynx_2 = ({1'b0, tmp_if_7_2} | {tmp_if_8_2, {(1'h1){1'b0}}});
                  if ((({1'b0, lynx_2} | {tmp_if_9_2, {(2'h2){1'b0}}}) == 3'h5)) begin
                    norma_2 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
                    octans_2 = ({1'b0, norma_2} | {tmp_if_1_2, {(2'h2){1'b0}}});
                    pictor_2 = ({1'b0, octans_2} | {tmp_if_2_2, {(2'h3){1'b0}}});
                    pyxis_2 = ({1'b0, pictor_2} | {tmp_if_3_2, {(3'h4){1'b0}}});
                    sagitta_2 = ({1'b0, pyxis_2} | {tmp_if_4_2, {(3'h5){1'b0}}});
                    serpens_2 = ({1'b0, sagitta_2} | {tmp_if_5_2, {(3'h6){1'b0}}});
                    fixed_11 = ((({1'b0, serpens_2} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err) ^ 8'h10);
                  end else begin
                    tucana_2 = ({1'b0, tmp_if_7_2} | {tmp_if_8_2, {(1'h1){1'b0}}});
                    if ((({1'b0, tucana_2} | {tmp_if_9_2, {(2'h2){1'b0}}}) == 3'h6)) begin
                      volans_2 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
                      vulpecula_2 = ({1'b0, volans_2} | {tmp_if_1_2, {(2'h2){1'b0}}});
                      orion_3 = ({1'b0, vulpecula_2} | {tmp_if_2_2, {(2'h3){1'b0}}});
                      lyra_3 = ({1'b0, orion_3} | {tmp_if_3_2, {(3'h4){1'b0}}});
                      cygnus_3 = ({1'b0, lyra_3} | {tmp_if_4_2, {(3'h5){1'b0}}});
                      draco_3 = ({1'b0, cygnus_3} | {tmp_if_5_2, {(3'h6){1'b0}}});
                      fixed_13 = ((({1'b0, draco_3} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err) ^ 8'h20);
                    end else begin
                      aquila_3 = ({1'b0, tmp_if_7_2} | {tmp_if_8_2, {(1'h1){1'b0}}});
                      if ((({1'b0, aquila_3} | {tmp_if_9_2, {(2'h2){1'b0}}}) == 3'h7)) begin
                        pegasus_3 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
                        perseus_3 = ({1'b0, pegasus_3} | {tmp_if_1_2, {(2'h2){1'b0}}});
                        andromeda_3 = ({1'b0, perseus_3} | {tmp_if_2_2, {(2'h3){1'b0}}});
                        phoenix_3 = ({1'b0, andromeda_3} | {tmp_if_3_2, {(3'h4){1'b0}}});
                        hydra_3 = ({1'b0, phoenix_3} | {tmp_if_4_2, {(3'h5){1'b0}}});
                        centaurus_3 = ({1'b0, hydra_3} | {tmp_if_5_2, {(3'h6){1'b0}}});
                        fixed_15 = ((({1'b0, centaurus_3} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err) ^ 8'h40);
                      end else begin
                        cassiopeia_3 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
                        carina_3 = ({1'b0, cassiopeia_3} | {tmp_if_1_2, {(2'h2){1'b0}}});
                        vela_3 = ({1'b0, carina_3} | {tmp_if_2_2, {(2'h3){1'b0}}});
                        auriga_3 = ({1'b0, vela_3} | {tmp_if_3_2, {(3'h4){1'b0}}});
                        cepheus_3 = ({1'b0, auriga_3} | {tmp_if_4_2, {(3'h5){1'b0}}});
                        columba_3 = ({1'b0, cepheus_3} | {tmp_if_5_2, {(3'h6){1'b0}}});
                        fixed_15 = ((({1'b0, columba_3} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err) ^ 8'h80);
                      end
                      fixed_13 = fixed_15;
                    end
                    fixed_11 = fixed_13;
                  end
                  fixed_9 = fixed_11;
                end
                fixed_7 = fixed_9;
              end
              fixed_5 = fixed_7;
            end
            fixed_3 = fixed_5;
          end
          cor_3 = 1'b1;
          fixed_17 = fixed_3;
          dbl_4 = 1'b0;
        end else begin
          corvus_3 = ({1'b0, tmp_if_7_2} | {tmp_if_8_2, {(1'h1){1'b0}}});
          if ((({1'b0, corvus_3} | {tmp_if_9_2, {(2'h2){1'b0}}}) != 3'h0)) begin
            dbl_3 = 1'b1;
          end else begin
            dbl_3 = 1'b0;
          end
          cor_3 = 1'b0;
          crux_3 = ({1'b0, tmp_if_2} | {tmp_if_0_2, {(1'h1){1'b0}}});
          fornax_3 = ({1'b0, crux_3} | {tmp_if_1_2, {(2'h2){1'b0}}});
          gemini_3 = ({1'b0, fornax_3} | {tmp_if_2_2, {(2'h3){1'b0}}});
          hercules_3 = ({1'b0, gemini_3} | {tmp_if_3_2, {(3'h4){1'b0}}});
          indus_3 = ({1'b0, hercules_3} | {tmp_if_4_2, {(3'h5){1'b0}}});
          lupus_3 = ({1'b0, indus_3} | {tmp_if_5_2, {(3'h6){1'b0}}});
          fixed_17 = (({1'b0, lupus_3} | {tmp_if_6_2, {(3'h7){1'b0}}}) ^ err);
          dbl_4 = dbl_3;
        end
        lynx_3 = (fixed_17[2 : 0] & 3'h4);
        if ((lynx_3[2 : 0] != 3'h0)) begin
          tmp_if_10_2 = 1'h1;
        end else begin
          tmp_if_10_2 = 1'h0;
        end
        norma_3 = (fixed_17[4 : 0] & 5'h10);
        if ((norma_3[4 : 0] != 5'h0)) begin
          tmp_if_11_2 = 1'h1;
        end else begin
          tmp_if_11_2 = 1'h0;
        end
        octans_3 = (fixed_17[5 : 0] & 6'h20);
        if ((octans_3[5 : 0] != 6'h0)) begin
          tmp_if_12_2 = 1'h1;
        end else begin
          tmp_if_12_2 = 1'h0;
        end
        pictor_3 = (fixed_17[6 : 0] & 7'h40);
        if ((pictor_3[6 : 0] != 7'h0)) begin
          tmp_if_13_2 = 1'h1;
        end else begin
          tmp_if_13_2 = 1'h0;
        end
        pyxis_3 = ({1'b0, tmp_if_10_2} | {tmp_if_11_2, {(1'h1){1'b0}}});
        sagitta_3 = ({1'b0, pyxis_3} | {tmp_if_12_2, {(2'h2){1'b0}}});
        dout <= ({1'b0, sagitta_3} | {tmp_if_13_2, {(2'h3){1'b0}}});
        dout_valid <= 1'b1;
        corrected <= cor_3;
        corrected_valid <= 1'b1;
        dblerr <= dbl_4;
        dblerr_valid <= 1'b1;
      end
    end
  end

endmodule //HammingEcc
