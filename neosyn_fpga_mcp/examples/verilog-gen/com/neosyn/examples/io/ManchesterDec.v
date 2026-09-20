
/**
 * ---------------------------------------------------------------- decoder
 * One line half-bit in per cycle; one recovered bit out per bit-time, flagged by
 * a one-cycle `valid`. `dout` HOLDS between valids — qualify it, same rule as
 * UartRx's byte and SpiMaster's `rx`.
 */
module ManchesterDec(input clock, input reset_n, input  line, input line_valid, output reg  dout, output reg dout_valid, output reg  valid, output reg valid_valid, output reg  viol, output reg viol_valid);


  /**
   * State variables
   */
  reg  p;
  reg  s1;
  reg  db;
  reg  v;
  reg  bad;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of ManchesterDec
    if (~reset_n) begin
      p <= 1'b0;
      s1 <= 1'b0;
      db <= 1'b0;
      v <= 1'b0;
      bad <= 1'b0;
      dout <= 1'b0;
      valid <= 1'b0;
      viol <= 1'b0;
      dout_valid <= 1'b0;
      valid_valid <= 1'b0;
      viol_valid <= 1'b0;
    end else begin
      dout_valid <= 1'b0;
      valid_valid <= 1'b0;
      viol_valid <= 1'b0;
      
      if (line_valid) begin : FSM_ManchesterDec_a // line 141
        reg  local_s1_3;
        reg  v_0_3;
        reg  bad_0_3;
        reg  db_0_3;
      
        dout <= db;
        dout_valid <= 1'b1;
        // publish the PREVIOUS result before overwriting it
        valid <= v;
        // publish the PREVIOUS result before overwriting it
        valid_valid <= 1'b1;
        viol <= bad;
        viol_valid <= 1'b1;
        if (! (p)) begin
          local_s1_3 = line;
          v_0_3 = 1'b0;
          bad_0_3 = 1'b0;
          db_0_3 = db;
        end else begin
          local_s1_3 = s1;
          v_0_3 = (s1 != line);
          bad_0_3 = (s1 == line);
          db_0_3 = line;
        end
        db <= db_0_3;
        v <= v_0_3;
        bad <= bad_0_3;
        p <= ! (p);
        s1 <= local_s1_3;
      end
    end
  end

endmodule //ManchesterDec
