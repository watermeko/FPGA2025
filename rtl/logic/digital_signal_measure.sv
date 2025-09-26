module digital_signal_measure(
    input clk,
    input rst_n,
    input measure_start,
    input measure_pin,

    output reg [15:0] high_time,
    output reg [15:0] low_time,
    output reg [15:0] period_time,
    output reg [15:0] duty_cycle,
    output reg measure_done
);

    // 状态定义
    localparam IDLE = 3'b000;
    localparam WAIT_RISING = 3'b001;
    localparam MEASURE_HIGH = 3'b010;
    localparam MEASURE_LOW = 3'b011;
    localparam CALCULATE = 3'b100;
    localparam DONE = 3'b101;

    reg [2:0] state, next_state;
    reg [15:0] high_counter;
    reg [15:0] low_counter;
    reg [15:0] period_counter;
    
    // 同步器，用于检测边沿
    reg measure_pin_sync1, measure_pin_sync2, measure_pin_sync3;
    wire rising_edge, falling_edge;
    
    // 边沿检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            measure_pin_sync1 <= 1'b0;
            measure_pin_sync2 <= 1'b0;
            measure_pin_sync3 <= 1'b0;
        end else begin
            measure_pin_sync1 <= measure_pin;
            measure_pin_sync2 <= measure_pin_sync1;
            measure_pin_sync3 <= measure_pin_sync2;
        end
    end
    
    assign rising_edge = measure_pin_sync2 & ~measure_pin_sync3;
    assign falling_edge = ~measure_pin_sync2 & measure_pin_sync3;

    // 状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // 状态转换逻辑
    always @(*) begin
        case (state)
            IDLE: begin
                if (measure_start)
                    next_state = WAIT_RISING;
                else
                    next_state = IDLE;
            end
            
            WAIT_RISING: begin
                if (rising_edge)
                    next_state = MEASURE_HIGH;
                else
                    next_state = WAIT_RISING;
            end
            
            MEASURE_HIGH: begin
                if (falling_edge)
                    next_state = MEASURE_LOW;
                else
                    next_state = MEASURE_HIGH;
            end
            
            MEASURE_LOW: begin
                if (rising_edge)
                    next_state = CALCULATE;
                else
                    next_state = MEASURE_LOW;
            end
            
            CALCULATE: begin
                next_state = DONE;
            end
            
            DONE: begin
                if (!measure_start)
                    next_state = IDLE;
                else
                    next_state = DONE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // 计数器逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            high_counter <= 16'b0;
            low_counter <= 16'b0;
            period_counter <= 16'b0;
        end else begin
            case (state)
                IDLE, WAIT_RISING: begin
                    high_counter <= 16'b0;
                    low_counter <= 16'b0;
                    period_counter <= 16'b0;
                end
                
                MEASURE_HIGH: begin
                    if (measure_pin_sync2) begin
                        high_counter <= high_counter + 1'b1;
                        period_counter <= period_counter + 1'b1;
                    end
                end
                
                MEASURE_LOW: begin
                    if (!measure_pin_sync2) begin
                        low_counter <= low_counter + 1'b1;
                        period_counter <= period_counter + 1'b1;
                    end
                end
            endcase
        end
    end

    // 输出寄存器更新
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            high_time <= 16'b0;
            low_time <= 16'b0;
            period_time <= 16'b0;
            duty_cycle <= 16'b0;
            measure_done <= 1'b0;
        end else begin
            case (state)
                CALCULATE: begin
                    high_time <= high_counter;
                    low_time <= low_counter;
                    period_time <= period_counter;
                    
                    // 计算占空比 (高电平时间 * 100 / 周期时间)
                    if (period_counter != 0)
                        duty_cycle <= (high_counter * 100) / period_counter;
                    else
                        duty_cycle <= 16'b0;
                end
                
                DONE: begin
                    measure_done <= 1'b1;
                end
                
                IDLE: begin
                    measure_done <= 1'b0;
                end
            endcase
        end
    end

endmodule