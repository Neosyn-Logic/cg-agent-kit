
/**
 * UART receiver — the canonical serial-IN control FSM, and the exact pair to UartTx.
 * 
 * Idle line high. A falling edge (the start bit) arms the machine; the next 8
 * cycles are shifted into a register LSB-first; the 10th cycle carries the stop
 * bit. `valid` pulses for ONE cycle when a frame is accepted, with `data` holding
 * the byte. Like UartTx, the "state" is a shift register (`sh`) plus a bit
 * counter (`cnt`) rather than a named enum — the right shape when the state is
 * really just "how many bits are left".
 * 
 * FRAMING CHECK: the byte is committed only if the stop bit is HIGH. A frame
 * with a low stop bit is shifted in, then dropped — `data` keeps its previous
 * value and `valid` never fires. Hang a `out bool err` off that same else-branch
 * if you want to report framing errors rather than silently discard them.
 * 
 * `data` HOLDS the last ACCEPTED byte between frames, so always qualify it with
 * `valid` — reading `data` on an arbitrary cycle gives you a stale byte, not a
 * new one.
 * 
 * One bit = one clock here, so this receiver pairs cycle-for-cycle with UartTx.
 * A real UART cannot do that: the line is asynchronous, so it oversamples (16x
 * is standard), detects the start edge, then samples each bit at its MIDPOINT
 * (8 ticks in, then every 16). To get there, drive this same machine from a
 * sample-tick enable instead of every clock — the FSM below is unchanged, only
 * the cadence that advances it changes.
 * 
 * Timing (as in every Cg FSM): a port reflects the register at the START of the
 * cycle, so publish the CURRENT `data`/`valid`/`busy` BEFORE updating the shift
 * register — a just-computed result would read back one cycle late. The
 * registers are inline-initialized (no setup(), which would add a reset state
 * that offsets the whole stream).
 */
module UartRx(input clock, input reset_n, input  rx, input rx_valid, output reg [7 : 0] data, output reg data_valid, output reg  valid, output reg valid_valid, output reg  busy, output reg busy_valid);


  /**
   * State variables
   */
  reg [7 : 0] sh;
  reg [3 : 0] cnt;
  reg [7 : 0] dout;
  reg  got;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of UartRx
    if (~reset_n) begin
      sh <= 8'h0;
      cnt <= 4'h0;
      dout <= 8'h0;
      got <= 1'b0;
      data <= 8'b0;
      valid <= 1'b0;
      busy <= 1'b0;
      data_valid <= 1'b0;
      valid_valid <= 1'b0;
      busy_valid <= 1'b0;
    end else begin
      data_valid <= 1'b0;
      valid_valid <= 1'b0;
      busy_valid <= 1'b0;
      
      if (rx_valid) begin : FSM_UartRx_a // line 55
        reg [3 : 0] cnt_0_3;
        reg [3 : 0] cnt_0_4;
        reg [7 : 0] tmp_if_2;
        reg [7 : 0] sh_0_3;
        reg [3 : 0] cnt_0_6;
        reg [7 : 0] dout_0_3;
        reg  got_0_4;
        reg [7 : 0] dout_0_4;
        reg  got_0_5;
        reg [7 : 0] sh_0_4;
        reg [7 : 0] dout_0_5;
        reg  got_0_6;
        reg [4 : 0] orion;
      
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        data <= dout;
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        data_valid <= 1'b1;
        valid <= got;
        valid_valid <= 1'b1;
        busy <= (cnt != 4'h0);
        busy_valid <= 1'b1;
        if ((cnt == 4'h0)) begin
          if (! (rx)) begin
            cnt_0_3 = 4'h9;
          end else begin
            cnt_0_3 = cnt;
          end
          cnt_0_4 = cnt_0_3;
          sh_0_4 = sh;
          dout_0_5 = dout;
          got_0_6 = 1'b0;
        end else begin
          if ((cnt > 4'h1)) begin
            // shift in from the TOP: the first bit received ends up in bit 0
            if (rx) begin
              tmp_if_2 = 8'h80;
            end else begin
              tmp_if_2 = 8'h0;
            end
            sh_0_3 = ((sh >> 8'h1) | tmp_if_2);
            orion = (cnt - 4'h1);
            cnt_0_6 = orion[3 : 0];
            dout_0_4 = dout;
            got_0_5 = 1'b0;
          end else begin
            // cnt == 1: this cycle carries the stop bit
            if (rx) begin
              dout_0_3 = sh;
              got_0_4 = 1'b1;
            end else begin
              dout_0_3 = dout;
              got_0_4 = 1'b0;
            end
            sh_0_3 = sh;
            cnt_0_6 = 4'h0;
            dout_0_4 = dout_0_3;
            got_0_5 = got_0_4;
          end
          cnt_0_4 = cnt_0_6;
          sh_0_4 = sh_0_3;
          dout_0_5 = dout_0_4;
          got_0_6 = got_0_5;
        end
        dout <= dout_0_5;
        got <= got_0_6;
        cnt <= cnt_0_4;
        sh <= sh_0_4;
      end
    end
  end

endmodule //UartRx
