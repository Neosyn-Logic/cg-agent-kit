/**
 * Title      : Generated from t.ScaleGen_src by Neosyn IDE
 * Project    : home
 *
 * File       : t.ScaleGen_src.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module ScaleGen_src(input clock, input reset_n, output reg [15 : 0] v, input v_ready, output reg v_valid);


  /**
   * State variables
   */
  reg  stall;
  
  
  
  /**
   * FSM
   */
  reg [1 : 0] FSM;
  
  localparam FSM_ScaleGen_src = 2'b00;
  localparam FSM_ScaleGen_src_1 = 2'b01;
  localparam FSM_ScaleGen_src_2 = 2'b10;
  localparam FSM_ScaleGen_src_3 = 2'b11;
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of ScaleGen_src
    if (~reset_n) begin
      stall <= 1'b0;
      v <= 16'b0;
      v_valid <= 1'b0;
      FSM <= FSM_ScaleGen_src;
    end else begin
      // Reset the flags of every OTHER synchronous output; the direct held output keeps its
      // valid (see below), so it must not be defaulted to 0 here.
      // Direct held-producer link (StreamLinkMarker): present the value and HOLD it until the
      // consumer takes it (ready). `v_valid`/`v` are registered, so they lag the FSM
      // by a cycle; advance the scheduler (loading the next value) ONLY when the current value is
      // accepted (v_ready) or none is presented yet (!v_valid). Otherwise every register
      // holds, so no value is dropped under consumer backpressure.
      if (v_ready || !v_valid) begin
        v_valid <= 1'b0;
        case (FSM)
          FSM_ScaleGen_src: begin
            begin // line 19
              v <= 16'h2;
              v_valid <= 1'b1;
              FSM <= FSM_ScaleGen_src_1;
              stall <= ! (v_ready);
            end
          end
        
          FSM_ScaleGen_src_1: begin
            begin // line 19
              v <= 16'h7;
              v_valid <= 1'b1;
              FSM <= FSM_ScaleGen_src_2;
              stall <= ! (v_ready);
            end
          end
        
          FSM_ScaleGen_src_2: begin
            begin // line 19
              v <= 16'h64;
              v_valid <= 1'b1;
              FSM <= FSM_ScaleGen_src_3;
              stall <= ! (v_ready);
            end
          end
        
          FSM_ScaleGen_src_3: begin
            begin // line 0
            end
          end
        
          // synthesis translate_off
          default: $stop;
          // synthesis translate_on
        endcase
      end
    end
  end

endmodule //ScaleGen_src
