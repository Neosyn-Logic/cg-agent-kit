
/**
 * SPI master (mode 0, MSB-first) — the clock-generating side of a synchronous
 * serial bus, and the standard way to talk to an ADC, DAC, flash, sensor or
 * display controller.
 * 
 * SPI is FULL DUPLEX: every transfer both sends and receives. One byte goes out
 * on MOSI while another comes back on MISO in the same eight bit-times — there
 * is no separate "read" transaction. To read a device register you clock out
 * the address and simultaneously clock in whatever the slave drives back, which
 * is why `tx` and `rx` are both present on a single `start` pulse.
 * 
 * Unlike a UART, the master OWNS the clock, so there is no baud agreement and
 * no start/stop framing: `csn` frames the transfer instead. That is the whole
 * difference between the two serial families, and why this block generates
 * `sclk` while UartRx has to recover timing from the data itself.
 * 
 * One SPI bit = TWO fabric clocks, tracked by the `ph` (phase) register:
 * ph=0  sclk LOW  — MOSI holds the current bit, stable for the slave
 * ph=1  sclk HIGH — the slave has sampled MOSI on the rising edge, and the
 * master samples MISO here; on the fall MOSI advances
 * That is mode 0 (CPOL=0 idle-low, CPHA=0 sample-on-leading-edge). For mode 3
 * (CPOL=1) invert `sclk` on the way out; for the CPHA=1 modes swap which half
 * samples and which shifts.
 * 
 * `rx` HOLDS the last received byte, so qualify it with `done` — exactly the
 * same rule as UartRx's `data`/`valid`.
 * 
 * TO ADAPT:
 * * slower sclk — one bit is two clocks here (sclk = fabric/2, the fastest
 * possible). Gate the body behind a Pwm `tick` to divide it down to a rate
 * the slave accepts; the FSM below is unchanged.
 * * wider transfers — widen `sh`/`rsh`/`tx`/`rx` and load `cnt` with the bit
 * count (16- and 24-bit frames are common for ADCs and flash commands).
 * * multi-byte transactions — hold `csn` low across several bytes instead of
 * releasing it at `cnt == 0`; most flash/display protocols require this.
 * * several slaves — one `csn` per device, all sharing sclk/mosi/miso.
 * 
 * Timing (as in every Cg FSM): a port reflects the register at the START of the
 * cycle, so publish the CURRENT sclk/mosi/csn BEFORE advancing the phase — a
 * just-computed level would read back one cycle late and skew the clock against
 * the data. The registers are inline-initialized (no setup(), which would add a
 * reset state that offsets the whole stream).
 */
module SpiMaster(input clock, input reset_n, input  start, input start_valid, input [7 : 0] tx, input tx_valid, input  miso, input miso_valid, output reg  sclk, output reg sclk_valid, output reg  mosi, output reg mosi_valid, output reg  csn, output reg csn_valid, output reg [7 : 0] rx, output reg rx_valid, output reg  done, output reg done_valid);


  /**
   * State variables
   */
  reg [7 : 0] sh;
  reg [7 : 0] rsh;
  reg [3 : 0] cnt;
  reg  ph;
  reg  active;
  reg [7 : 0] dout;
  reg  dn;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of SpiMaster
    if (~reset_n) begin
      sh <= 8'h0;
      rsh <= 8'h0;
      cnt <= 4'h0;
      ph <= 1'b0;
      active <= 1'b0;
      dout <= 8'h0;
      dn <= 1'b0;
      sclk <= 1'b0;
      mosi <= 1'b0;
      csn <= 1'b0;
      rx <= 8'b0;
      done <= 1'b0;
      sclk_valid <= 1'b0;
      mosi_valid <= 1'b0;
      csn_valid <= 1'b0;
      rx_valid <= 1'b0;
      done_valid <= 1'b0;
    end else begin
      sclk_valid <= 1'b0;
      mosi_valid <= 1'b0;
      csn_valid <= 1'b0;
      rx_valid <= 1'b0;
      done_valid <= 1'b0;
      
      if (((start_valid && tx_valid) && miso_valid)) begin : FSM_SpiMaster_a // line 76
        reg [7 : 0] sh_0_3;
        reg [7 : 0] local_rsh_3;
        reg [3 : 0] local_cnt_3;
        reg  ph_0_3;
        reg  active_0_3;
        reg [7 : 0] sh_0_4;
        reg [7 : 0] local_rsh_4;
        reg [3 : 0] local_cnt_4;
        reg  ph_0_4;
        reg  active_0_4;
        reg  ph_0_6;
        reg [7 : 0] tmp_if_2;
        reg [7 : 0] local_rsh_6;
        reg [7 : 0] sh_0_6;
        reg [3 : 0] local_cnt_5;
        reg [3 : 0] local_cnt_6;
        reg  active_0_6;
        reg [7 : 0] dout_0_3;
        reg  dn_0_4;
        reg  active_0_7;
        reg [7 : 0] dout_0_4;
        reg  dn_0_5;
        reg [7 : 0] dout_0_5;
        reg  dn_0_6;
        reg [4 : 0] orion;
        reg [8 : 0] lyra;
        reg [8 : 0] cygnus;
        reg [8 : 0] draco;
        reg [8 : 0] aquila;
        reg [8 : 0] pegasus;
      
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        csn <= ! (active);
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        csn_valid <= 1'b1;
        sclk <= ph;
        sclk_valid <= 1'b1;
        mosi <= ((sh & 8'h80) != 8'h0);
        mosi_valid <= 1'b1;
        // bool port: write the bit itself, don't compare it
        rx <= dout;
        // bool port: write the bit itself, don't compare it
        rx_valid <= 1'b1;
        done <= dn;
        done_valid <= 1'b1;
        if (! (active)) begin
          if (start) begin
            sh_0_3 = tx;
            local_rsh_3 = 8'h0;
            local_cnt_3 = 4'h8;
            ph_0_3 = 1'b0;
            active_0_3 = 1'b1;
          end else begin
            sh_0_3 = sh;
            local_rsh_3 = rsh;
            local_cnt_3 = cnt;
            ph_0_3 = ph;
            active_0_3 = active;
          end
          sh_0_4 = sh_0_3;
          local_rsh_4 = local_rsh_3;
          local_cnt_4 = local_cnt_3;
          ph_0_4 = ph_0_3;
          active_0_4 = active_0_3;
          dout_0_5 = dout;
          dn_0_6 = 1'b0;
        end else begin
          if (! (ph)) begin
            ph_0_6 = 1'b1;
            local_rsh_6 = rsh;
            sh_0_6 = sh;
            local_cnt_6 = cnt;
            active_0_7 = active;
            dout_0_4 = dout;
            dn_0_5 = 1'b0;
          end else begin
            // sclk high: sample MISO, then advance MOSI as the clock falls
            if (miso) begin
              tmp_if_2 = 8'h1;
            end else begin
              tmp_if_2 = 8'h0;
            end
            orion = (cnt - 4'h1);
            local_cnt_5 = orion[3 : 0];
            if ((local_cnt_5 == 4'h0)) begin
              active_0_6 = 1'b0;
              lyra = {rsh, {(1'h1){1'b0}}};
              cygnus = (lyra[7 : 0] | tmp_if_2);
              dout_0_3 = cygnus[7 : 0];
              dn_0_4 = 1'b1;
            end else begin
              active_0_6 = active;
              dout_0_3 = dout;
              dn_0_4 = 1'b0;
            end
            ph_0_6 = 1'b0;
            draco = {rsh, {(1'h1){1'b0}}};
            aquila = (draco[7 : 0] | tmp_if_2);
            local_rsh_6 = aquila[7 : 0];
            pegasus = {sh, {(1'h1){1'b0}}};
            sh_0_6 = pegasus[7 : 0];
            local_cnt_6 = local_cnt_5;
            active_0_7 = active_0_6;
            dout_0_4 = dout_0_3;
            dn_0_5 = dn_0_4;
          end
          sh_0_4 = sh_0_6;
          local_rsh_4 = local_rsh_6;
          local_cnt_4 = local_cnt_6;
          ph_0_4 = ph_0_6;
          active_0_4 = active_0_7;
          dout_0_5 = dout_0_4;
          dn_0_6 = dn_0_5;
        end
        active <= active_0_4;
        ph <= ph_0_4;
        sh <= sh_0_4;
        dout <= dout_0_5;
        dn <= dn_0_6;
        rsh <= local_rsh_4;
        cnt <= local_cnt_4;
      end
    end
  end

endmodule //SpiMaster
