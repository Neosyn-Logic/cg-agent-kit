/**
 * Title      : Generated from com.neosyn.examples.io.Manchester_test_monitor by Neosyn IDE
 * Project    : home
 *
 * File       : com.neosyn.examples.io.Manchester_test_monitor.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module Manchester_test_monitor(input clock, input reset_n, input  dout, input dout_valid, input  valid, input valid_valid);


  /**
   * State variables
   */
  reg [7 : 0] got;
  reg [3 : 0] n;
  reg  finished;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Manchester_test_monitor
    if (~reset_n) begin
      got <= 8'h0;
      n <= 4'h0;
      finished <= 1'b0;
    end else begin
      
      if ((dout_valid && valid_valid)) begin : FSM_Manchester_test_monitor_a // line 192
        reg [7 : 0] got_0_3;
        reg [7 : 0] got_0_5;
        reg [3 : 0] n_0_3;
        reg [8 : 0] orion;
        reg [8 : 0] lyra;
        reg [8 : 0] cygnus;
        reg [4 : 0] draco;
        reg [4 : 0] aquila;
      
        if (valid) begin
          if (dout) begin
            orion = {got, {(1'h1){1'b0}}};
            lyra = (orion[7 : 0] | 8'h1);
            got_0_3 = lyra[7 : 0];
          end else begin
            cygnus = {got, {(1'h1){1'b0}}};
            got_0_3 = cygnus[7 : 0];
          end
          draco = (n + 4'h1);
          if ((draco[3 : 0] == 4'h8)) begin
            // synthesis translate_off
            $display("Manchester round trip = %0h (expect 0xB2)\n", got_0_3);
            // synthesis translate_on
            // synthesis translate_off
            if (~((got_0_3 == 8'hb2))) begin
              $display("Assertion failed: (got_0_3 == 8'hb2)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
          end
          got_0_5 = got_0_3;
          aquila = (n + 4'h1);
          n_0_3 = aquila[3 : 0];
        end else begin
          got_0_5 = got;
          n_0_3 = n;
        end
        got <= got_0_5;
        n <= n_0_3;
      end
    end
  end

endmodule //Manchester_test_monitor
