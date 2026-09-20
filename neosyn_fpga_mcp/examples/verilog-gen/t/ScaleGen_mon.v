/**
 * Title      : Generated from t.ScaleGen_mon by Neosyn IDE
 * Project    : home
 *
 * File       : t.ScaleGen_mon.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module ScaleGen_mon(input clock, input reset_n, input [31 : 0] r, input r_valid, output reg r_ready);


  /**
   * State variables
   */
  reg  finished;
  
  
  
  /**
   * FSM
   */
  reg [1 : 0] FSM;
  
  localparam FSM_ScaleGen_mon = 2'b00;
  localparam FSM_ScaleGen_mon_1 = 2'b01;
  localparam FSM_ScaleGen_mon_2 = 2'b10;
  localparam FSM_ScaleGen_mon_3 = 2'b11;
  
  
  /**
   * Combinational process
   */
  always @(*) begin
    r_ready = 1'b0;
    case (FSM)
      FSM_ScaleGen_mon: begin
        if (r_valid) begin // line 27
          r_ready = 1'b1;
        end else begin // line 0
          r_ready = ! (r_valid);
        end
      end
    
      FSM_ScaleGen_mon_1: begin
        if (r_valid) begin // line 28
          r_ready = 1'b1;
        end else begin // line 0
          r_ready = ! (r_valid);
        end
      end
    
      FSM_ScaleGen_mon_2: begin
        if (r_valid) begin // line 29
          r_ready = 1'b1;
        end else begin // line 0
          r_ready = ! (r_valid);
        end
      end
    
      FSM_ScaleGen_mon_3: begin
        begin // line 0
        end
      end
    
    endcase
  end
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of ScaleGen_mon
    if (~reset_n) begin
      finished <= 1'b0;
      FSM <= FSM_ScaleGen_mon;
    end else begin
      
      case (FSM)
        FSM_ScaleGen_mon: begin
          if (r_valid) begin // line 27
            // synthesis translate_off
            if (~((r == 32'ha))) begin
              $display("Assertion failed: (r == 32'ha)");
              $stop;
            end
            // synthesis translate_on
            FSM <= FSM_ScaleGen_mon_1;
          end else begin // line 0
          end
        end
      
        FSM_ScaleGen_mon_1: begin
          if (r_valid) begin // line 28
            // synthesis translate_off
            if (~((r == 32'h23))) begin
              $display("Assertion failed: (r == 32'h23)");
              $stop;
            end
            // synthesis translate_on
            FSM <= FSM_ScaleGen_mon_2;
          end else begin // line 0
          end
        end
      
        FSM_ScaleGen_mon_2: begin
          if (r_valid) begin // line 29
            // synthesis translate_off
            if (~((r == 32'h1f4))) begin
              $display("Assertion failed: (r == 32'h1f4)");
              $stop;
            end
            // synthesis translate_on
            // 100*5
            finished <= 1'b1;
            FSM <= FSM_ScaleGen_mon_3;
          end else begin // line 0
          end
        end
      
        FSM_ScaleGen_mon_3: begin
          begin // line 0
          end
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //ScaleGen_mon
