module i2c_handler(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  cmd_type,
    input  wire [15:0] cmd_length,
    input  wire [7:0]  cmd_data,
    input  wire [15:0] cmd_data_index,
    input  wire        cmd_start,
    input  wire        cmd_data_valid,
    input  wire        cmd_done,

    output wire        cmd_ready,

    output wire        i2c_sclk,
    inout  wire        i2c_sdat,
    

    // 数据上传接口
    output reg         upload_req,        // 上传请求
    output reg  [7:0]  upload_data,       // 上传数据  
    output reg  [7:0]  upload_source,     // 数据源标识
    output reg         upload_valid,      // 上传数据有效
    input  wire        upload_ready       // 上传准备就绪
);

    // Command type codes
    localparam CMD_I2C_CONFIG = 8'h04;
    localparam CMD_I2C_TX     = 8'h05;
    localparam CMD_I2C_RX     = 8'h06;

    // Upload source identifier for I2C
    localparam UPLOAD_SOURCE_I2C = 8'h02;

    // State machine definition
    localparam H_IDLE         = 4'b0001; // Idle state
    localparam H_RX_CONFIG    = 4'b0010; // Receiving I2C configuration
    localparam H_UPDATE_CFG   = 4'b0011; // Update configuration
    localparam H_RX_TX_DATA   = 4'b0100; // Receiving data to transmit
    localparam H_DO_WRITE     = 4'b0101; // Perform I2C Write
    localparam H_RX_RX_CMD    = 4'b0110; // Handling I2C receive command (parse lengths)
    localparam H_DO_READ      = 4'b0111; // Perform I2C Read (issue requests)
    localparam H_WAIT_DONE    = 4'b1000; // Wait for single I2C operation to complete
    localparam H_UPLOAD_DATA  = 4'b1001; // Uploading received data

    reg [3:0] handler_state;

    // I2C Configuration & Control Registers
    reg [31:0] i2c_clk_freq;
    reg [6:0]  i2c_slave_addr;
    reg [15:0] i2c_reg_addr;
    reg [15:0] i2c_read_len;

    // I2C control signals
    reg wrreg_req_reg;
    reg rdreg_req_reg;
    wire i2c_rw_done;
    wire [7:0] rddata;
    wire ack;

    // Temporary storage for command payload
    reg [7:0] i2c_config_data [0:4]; // 4 bytes freq + 1 byte addr
    reg [7:0] wrdata;
    reg [15:0] i2c_tx_data_len;
    reg [7:0] i2c_tx_data [0:255]; // store tx data
    reg [7:0] i2c_rx_cmd_data [0:2]; // not used heavily here

    // Upload FIFO (stores received bytes to be uploaded)
    reg [7:0] upload_fifo [0:255];
    reg [7:0] upload_fifo_wr_ptr;
    reg [7:0] upload_fifo_rd_ptr;
    reg [8:0] upload_fifo_count;
    wire      upload_fifo_empty;
    wire      upload_fifo_full;

    // internal counters and indices
    reg [15:0] rx_req_remaining; // remaining bytes to read
    reg [15:0] tx_req_remaining; // remaining bytes to write
    reg [7:0]  current_reg_addr; // base reg addr for operations
    reg        pending_op_is_read; // 1: read op in progress, 0: write op
    reg        i2c_request_in_flight; // to indicate we've issued wr/rd and waiting for done

    // Upload FSM states
    localparam UP_IDLE = 2'b00;
    localparam UP_SEND = 2'b01;
    localparam UP_WAIT = 2'b10;
    reg [1:0] upload_state;

    // Ready to accept new commands
    assign cmd_ready = (handler_state == H_IDLE) 
                       || (handler_state == H_RX_CONFIG) 
                       || ((handler_state == H_RX_TX_DATA) && (i2c_tx_data_len < 256 || tx_req_remaining < 256));

    assign upload_fifo_empty = (upload_fifo_count == 0);
    assign upload_fifo_full  = (upload_fifo_count == 256);

    // Instantiate lower-level I2C controller (interface as in your original)
    i2c_control u_i2c_control(
        .Clk            (clk),
        .Rst_n          (rst_n),
        
        .wrreg_req      (wrreg_req_reg),
        .rdreg_req      (rdreg_req_reg),
        .addr           (i2c_reg_addr),
        .addr_mode      (1'b1), // 16-bit addr mode (we put 0 in high byte when using 8-bit reg)
        .wrdata         (wrdata), 
        .rddata         (rddata),
        .device_id      ({i2c_slave_addr, 1'b0}), // 7-bit + r/w bit place-hold, .device_id      ({i2c_slave_addr, 1'b0})
        // 针对实验使用的eeprom 是1010 +3 位片选信号，第二部验证使用oled
        .RW_Done        (i2c_rw_done),
        
        .ack            (ack),

        .i2c_sclk       (i2c_sclk),
        .i2c_sdat       (i2c_sdat)
    );

    // Reset and state machine
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state <= H_IDLE;
            i2c_clk_freq <= 32'd0;
            i2c_slave_addr <= 7'd0;
            i2c_reg_addr <= 16'd0;
            i2c_read_len <= 16'd0;

            wrreg_req_reg <= 1'b0;
            rdreg_req_reg <= 1'b0;
            wrdata <= 8'd0;
            i2c_tx_data_len <= 16'd0;
            tx_req_remaining <= 16'd0;
            rx_req_remaining <= 16'd0;
            current_reg_addr <= 8'd0;
            pending_op_is_read <= 1'b0;
            i2c_request_in_flight <= 1'b0;

            // clear config buffer
            for (i = 0; i < 5; i = i + 1) begin
                i2c_config_data[i] <= 8'h00;
            end
            // clear tx buffer
            for (i = 0; i < 256; i = i + 1) begin
                i2c_tx_data[i] <= 8'h00;
                upload_fifo[i] <= 8'h00;
            end
            upload_fifo_wr_ptr <= 8'd0;
            upload_fifo_rd_ptr <= 8'd0;
            upload_fifo_count <= 9'd0;

            upload_req <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= UPLOAD_SOURCE_I2C;
            upload_valid <= 1'b0;
            upload_state <= UP_IDLE;
        end else begin
            // default pulse signals off
            wrreg_req_reg <= 1'b0;
            rdreg_req_reg <= 1'b0;
            upload_valid <= 1'b0;
            upload_req <= 1'b0;

            case (handler_state)
                H_IDLE: begin
                    // wait for command start
                    if (cmd_start) begin
                        case (cmd_type)
                            CMD_I2C_CONFIG: begin
                                handler_state <= H_RX_CONFIG;
                            end
                            CMD_I2C_TX: begin
                                // prepare to receive tx payload (addr + data...)
                                i2c_tx_data_len <= 16'd0;
                                handler_state <= H_RX_TX_DATA;
                            end
                            CMD_I2C_RX: begin
                                // for RX we'll first collect the small header (1+2 bytes) by using RX state,
                                // But since cmd_data comes in with cmd_data_index we can use H_RX_RX_CMD to gather them.
                                handler_state <= H_RX_RX_CMD;
                            end
                            default: begin
                                handler_state <= H_IDLE;
                            end
                        endcase
                    end
                end

                // --- configuration receive ---
                H_RX_CONFIG: begin
                    // expecting exactly 5 bytes: [freq(4)][slave_addr(1)]
                    if (cmd_data_valid) begin
                        // store by cmd_data_index (0..4)
                        if (cmd_data_index <= 5) begin
                            i2c_config_data[cmd_data_index] <= cmd_data;
                        end
                    end
                    if (cmd_done) begin
                        handler_state <= H_UPDATE_CFG;
                    end
                end

                H_UPDATE_CFG: begin
                    // assemble frequency and slave address
                    i2c_clk_freq <= {i2c_config_data[0], i2c_config_data[1], i2c_config_data[2], i2c_config_data[3]};
                    i2c_slave_addr <= i2c_config_data[4][6:0];
                    handler_state <= H_IDLE;
                end

                // --- TX data reception ---
                H_RX_TX_DATA: begin
                    // cmd_data_index: 0 is register address, subsequent are data bytes
                    if (cmd_data_valid) begin
                        if (cmd_data_index == 16'd0) begin
                            current_reg_addr <= cmd_data; // base reg addr
                        end else begin
                            // store data starting at index-1
                            if ((cmd_data_index - 1) < 256) begin
                                i2c_tx_data[cmd_data_index - 1] <= cmd_data;
                            end
                        end
                        // update length measured as (cmd_length - 1) data bytes
                        // but keep explicit len logic at cmd_done
                    end

                    if (cmd_done) begin
                        // cmd_length includes 1 byte reg addr + N data bytes
                        if (cmd_length >= 1) begin
                            tx_req_remaining <= (cmd_length - 1); // number of data bytes to write
                            i2c_tx_data_len <= (cmd_length - 1);
                            // set starting reg addr in i2c_reg_addr (16-bit)
                            i2c_reg_addr <= {8'h00, current_reg_addr};
                            // prepare to do write flow
                            pending_op_is_read <= 1'b0;
                            handler_state <= H_DO_WRITE;
                        end else begin
                            // nothing to write
                            handler_state <= H_IDLE;
                        end
                    end
                end

                // --- perform write operations ---
                H_DO_WRITE: begin
                    // If no remaining, complete
                    if (tx_req_remaining == 0 && !i2c_request_in_flight) begin
                        handler_state <= H_IDLE;
                    end else begin
                        // if not currently waiting on lower-level op, issue next write
                        if (!i2c_request_in_flight) begin
                            // prepare wrdata: from i2c_tx_data array index = (i2c_tx_data_len - tx_req_remaining)
                            // compute index
                            reg [7:0] tx_index;
                            tx_index = i2c_tx_data_len[7:0] - tx_req_remaining[7:0];
                            wrdata <= i2c_tx_data[tx_index];
                            // set address low byte to current_reg_addr + offset
                            i2c_reg_addr <= {8'h00, current_reg_addr + tx_index};
                            // assert write request (pulse/hold)
                            wrreg_req_reg <= 1'b1;
                            i2c_request_in_flight <= 1'b1;
                        end
                        // else wait for completion in WAIT state via i2c_rw_done catch below
                    end
                end

                // --- receive RX command header (1 byte addr + 2 bytes length) ---
                H_RX_RX_CMD: begin
                    // Expect cmd_data_index=0 -> reg addr, 1->len_hi, 2->len_lo
                    if (cmd_data_valid) begin
                        if (cmd_data_index == 16'd0) begin
                            current_reg_addr <= cmd_data;
                        end else if (cmd_data_index == 16'd1) begin
                            i2c_rx_cmd_data[0] <= cmd_data; // len high
                        end else if (cmd_data_index == 16'd2) begin
                            i2c_rx_cmd_data[1] <= cmd_data; // len low
                        end
                    end

                    if (cmd_done) begin
                        // assemble read length
                        i2c_read_len <= {i2c_rx_cmd_data[0], i2c_rx_cmd_data[1]};
                        // prepare read remaining count
                        rx_req_remaining <= {i2c_rx_cmd_data[0], i2c_rx_cmd_data[1]};
                        // set base reg address
                        i2c_reg_addr <= {8'h00, current_reg_addr};
                        pending_op_is_read <= 1'b1;
                        // start reading
                        handler_state <= H_DO_READ;
                    end
                end

                // --- perform read operations (issue rd requests one-by-one) ---
                H_DO_READ: begin
                    // if nothing to read, go to upload stage (may be empty)
                    if ((rx_req_remaining == 0) && !i2c_request_in_flight) begin
                        handler_state <= H_UPLOAD_DATA;
                    end else begin
                        if (!i2c_request_in_flight) begin
                            // ensure FIFO has space
                            if (!upload_fifo_full) begin
                                // issue a read for the current addr + offset
                                reg [7:0] read_index;
                                reg [15:0] tmp_val;
                                tmp_val = i2c_read_len - rx_req_remaining;
                                read_index = tmp_val[7:0];
                                i2c_reg_addr <= {8'h00, current_reg_addr + read_index};
                                rdreg_req_reg <= 1'b1;
                                i2c_request_in_flight <= 1'b1;
                            end else begin
                                // FIFO full: stall here until upload consumes entries (upload logic may run in parallel).
                                // We stay in this state without issuing more reads.
                                // handler_state unchanged.
                            end
                        end
                        // wait for completion via i2c_rw_done handling below
                    end
                end

                // --- upload data state ---
                H_UPLOAD_DATA: begin
                    // H_UPLOAD_DATA stays while upload FSM sends FIFO out. When FIFO empty => back to IDLE.
                    if (upload_fifo_empty) begin
                        handler_state <= H_IDLE;
                    end else begin
                        handler_state <= H_UPLOAD_DATA;
                    end
                end

                default: begin
                    handler_state <= H_IDLE;
                end
            endcase

            // catch i2c_rw_done transitions (common for rd/wr)
            if (i2c_rw_done) begin
                // a lower-level op completed
                // determine whether the operation was a read or write by pending_op_is_read or rdreg_req_reg/wrreg_req_reg? 
                // We used i2c_request_in_flight to mark presence of an outstanding request.
                i2c_request_in_flight <= 1'b0;

                if (pending_op_is_read && (handler_state == H_DO_READ || handler_state == H_WAIT_DONE || handler_state == H_DO_READ)) begin
                    // read completion: rddata is valid; push into upload fifo if space
                    if (!upload_fifo_full) begin
                        upload_fifo[upload_fifo_wr_ptr] <= rddata;
                        upload_fifo_wr_ptr <= upload_fifo_wr_ptr + 1;
                        upload_fifo_count <= upload_fifo_count + 1;
                    end
                    // decrement remaining count
                    if (rx_req_remaining != 0) begin
                        rx_req_remaining <= rx_req_remaining - 1;
                    end
                    // stay in H_DO_READ to issue next read (or go to upload when 0)
                    // handler_state left to main FSM logic
                end else begin
                    // write completion
                    if (tx_req_remaining != 0) begin
                        tx_req_remaining <= tx_req_remaining - 1;
                    end
                    // check if there are more writes; if none, FSM will return to idle
                end
            end

            // Upload FSM - drives upload_req/upload_valid/upload_data using upload_fifo
            case (upload_state)
                UP_IDLE: begin
                    if ((handler_state == H_UPLOAD_DATA) && !upload_fifo_empty && upload_ready) begin
                        // present data
                        upload_req <= 1'b1;
                        upload_valid <= 1'b1;
                        upload_data <= upload_fifo[upload_fifo_rd_ptr];
                        upload_source <= UPLOAD_SOURCE_I2C;
                        upload_state <= UP_SEND;
                    end else begin
                        upload_state <= UP_IDLE;
                    end
                end

                UP_SEND: begin
                    // wait for receiver to accept (upload_ready)
                    if (upload_ready) begin
                        // commit read pointer change
                        upload_fifo_rd_ptr <= upload_fifo_rd_ptr + 1;
                        upload_fifo_count <= upload_fifo_count - 1;
                        upload_state <= UP_WAIT;
                        // de-assert request/valid next cycle (we already drive them low by default at top)
                    end
                end

                UP_WAIT: begin
                    // after one cycle, check if more data to send
                    if ((handler_state == H_UPLOAD_DATA) && !upload_fifo_empty && upload_ready) begin
                        upload_state <= UP_IDLE; // loops back to send next
                    end else if (upload_fifo_empty) begin
                        upload_state <= UP_IDLE;
                    end else begin
                        upload_state <= UP_WAIT;
                    end
                end

                default: upload_state <= UP_IDLE;
            endcase
        end
    end
endmodule