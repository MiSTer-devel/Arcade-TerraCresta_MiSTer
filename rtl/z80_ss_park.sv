// Parks the T80pa at an instruction boundary whose REG output is complete, for save states
module z80_ss_park
(
    input          clk,
    input          reset,      // z80 reset
    input          ce,         // T80pa CEN_p / CEN_n before gating
    input          park,       // request to park
    input          M1_n,
    input          MREQ_n,
    input          HALT_n,
    input    [7:0] din,        // z80 data in
    input  [211:0] reg_in,     // T80pa REG
    output         run,        // clock enable gate while parking
    output reg     parked,     // held in T2 of a safe opcode fetch
    output [211:0] reg_ss      // REG to save
);

localparam P_WAIT = 2'd0, P_STEP = 2'd1, P_HOLD = 2'd2, P_PARK = 2'd3;

reg  [1:0] state;
reg  [1:0] steps;
reg        m1_d;
reg  [7:0] op_q, last_op;

// last fetch was a prefix or EI
wire after_prefix = last_op == 8'hcb || last_op == 8'hdd || last_op == 8'hed || last_op == 8'hfd || last_op == 8'hfb;
// int-ack fetch (MREQ_n high), or a fetch after a prefix or EI while not halted
wire unsafe       = MREQ_n | (HALT_n & after_prefix);

assign run    = state == P_WAIT || state == P_STEP;
// halted cpu saves the HALT address so a restore halts again
assign reg_ss = { reg_in[211:80], reg_in[79:64] - { 15'd0, ~HALT_n }, reg_in[63:0] };

always @(posedge clk) begin
    m1_d <= M1_n;

    // opcode byte of the last fetch, latched when M1_n rises
    if (!M1_n) op_q <= din;
    if (!m1_d && M1_n) last_op <= op_q;
    if (reset) begin
        op_q    <= 8'h00;
        last_op <= 8'h00;
    end

    if (!park) begin
        state  <= P_WAIT;
        parked <= 0;
    end else begin
        case (state)
            // wait for the next opcode fetch
            P_WAIT: if (m1_d && !M1_n) begin
                steps <= 0;
                state <= P_STEP;
            end

            // run through T1, where the previous instruction writes its register
            P_STEP: if (ce) begin
                steps <= steps + 1'd1;
                if (steps == 2'd2) state <= P_HOLD;
            end

            // held in T2: keep it, or run on to the next fetch
            P_HOLD: if (unsafe) state <= P_WAIT;
                    else begin
                        parked <= 1;
                        state  <= P_PARK;
                    end

            default: ;
        endcase
    end
end

endmodule
