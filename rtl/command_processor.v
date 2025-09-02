module command_processor (
    input               clk,
    input               rst_n,

    // --- Inputs from protocol_parser ---
    input               parse_done,     // Trigger signal indicating a valid command
    input      [7:0]    cmd_out,        // The command code itself

    // --- Outputs to control other hardware ---
    output reg         led_out         // Output to control an LED
);

//-----------------------------------------------------------------------------
// Command Processing Logic
//-----------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // On reset, turn the LED off.
        led_out <= 1'b0;
    end else begin
        // Check for the trigger signal from the parser on every clock cycle.
        if (parse_done) begin
            // A valid command has been received. Check if it's the one we want.
            if (cmd_out == 8'hFF) begin
                // It's the heartbeat command! Toggle the LED's state.
                led_out <= ~led_out;
            end
            // You can add other commands here using 'else if'
            // else if (cmd_out == 8'h01) begin
            //     // Do something else for command 0x01
            // end
        end
    end
end

endmodule