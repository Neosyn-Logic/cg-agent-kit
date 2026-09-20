/**
 * Title      : Generated from com.example.FifoPipe_consumer by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.FifoPipe_consumer.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module FifoPipe_consumer(input clock, input reset_n, input [7 : 0] din, input din_valid, output reg din_ready);


  /**
   * State variables
   */
  reg  finished;
  reg [7 : 0] FSM_FifoPipe_consumer_a_a;
  reg [7 : 0] FSM_FifoPipe_consumer_1_a_b;
  reg [7 : 0] FSM_FifoPipe_consumer_2_a_c;
  
  
  
  /**
   * FSM
   */
  reg [2 : 0] FSM;
  
  localparam FSM_FifoPipe_consumer = 3'b000;
  localparam FSM_FifoPipe_consumer_1 = 3'b001;
  localparam FSM_FifoPipe_consumer_2 = 3'b010;
  localparam FSM_FifoPipe_consumer_3 = 3'b011;
  localparam FSM_FifoPipe_consumer_4 = 3'b100;
  
  
  /**
   * Combinational process
   */
  always @(*) begin
    din_ready = 1'b0;
    case (FSM)
      FSM_FifoPipe_consumer: begin
        if (din_valid) begin // line 25
          din_ready = 1'b1;
        end else begin // line 0
          din_ready = ! (din_valid);
        end
      end
    
      FSM_FifoPipe_consumer_1: begin
        if (din_valid) begin // line 26
          din_ready = 1'b1;
        end else begin // line 0
          din_ready = ! (din_valid);
        end
      end
    
      FSM_FifoPipe_consumer_2: begin
        if (din_valid) begin // line 27
          din_ready = 1'b1;
        end else begin // line 0
          din_ready = ! (din_valid);
        end
      end
    
      FSM_FifoPipe_consumer_3: begin
        if (din_valid) begin // line 28
          din_ready = ! (din_valid);
        end else begin // line 0
          din_ready = ! (din_valid);
        end
      end
    
      FSM_FifoPipe_consumer_4: begin
        begin // line 0
        end
      end
    
    endcase
  end
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of FifoPipe_consumer
    if (~reset_n) begin
      finished <= 1'b0;
      FSM_FifoPipe_consumer_a_a <= 8'b0;
      FSM_FifoPipe_consumer_1_a_b <= 8'b0;
      FSM_FifoPipe_consumer_2_a_c <= 8'b0;
      FSM <= FSM_FifoPipe_consumer;
    end else begin
      
      case (FSM)
        FSM_FifoPipe_consumer: begin
          if (din_valid) begin // line 25
            FSM_FifoPipe_consumer_a_a <= din;
            FSM <= FSM_FifoPipe_consumer_1;
          end else begin // line 0
          end
        end
      
        FSM_FifoPipe_consumer_1: begin
          if (din_valid) begin // line 26
            // each read stalls until a value is available
            FSM_FifoPipe_consumer_1_a_b <= din;
            FSM <= FSM_FifoPipe_consumer_2;
          end else begin // line 0
          end
        end
      
        FSM_FifoPipe_consumer_2: begin
          if (din_valid) begin // line 27
            FSM_FifoPipe_consumer_2_a_c <= din;
            FSM <= FSM_FifoPipe_consumer_3;
          end else begin // line 0
          end
        end
      
        FSM_FifoPipe_consumer_3: begin
          if (din_valid) begin // line 28
            // synthesis translate_off
            $display("fifo out = %0h %0h %0h %0h\n", FSM_FifoPipe_consumer_a_a, FSM_FifoPipe_consumer_1_a_b, FSM_FifoPipe_consumer_2_a_c, din);
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_FifoPipe_consumer_a_a == 8'h1))) begin
              $display("Assertion failed: (FSM_FifoPipe_consumer_a_a == 8'h1)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_FifoPipe_consumer_1_a_b == 8'h2))) begin
              $display("Assertion failed: (FSM_FifoPipe_consumer_1_a_b == 8'h2)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((FSM_FifoPipe_consumer_2_a_c == 8'h3))) begin
              $display("Assertion failed: (FSM_FifoPipe_consumer_2_a_c == 8'h3)");
              $stop;
            end
            // synthesis translate_on
            // synthesis translate_off
            if (~((din == 8'h4))) begin
              $display("Assertion failed: (din == 8'h4)");
              $stop;
            end
            // synthesis translate_on
            finished <= 1'b1;
            FSM <= FSM_FifoPipe_consumer_4;
          end else begin // line 0
          end
        end
      
        FSM_FifoPipe_consumer_4: begin
          begin // line 0
          end
        end
      
        // synthesis translate_off
        default: $stop;
        // synthesis translate_on
      endcase
    end
  end

endmodule //FifoPipe_consumer
