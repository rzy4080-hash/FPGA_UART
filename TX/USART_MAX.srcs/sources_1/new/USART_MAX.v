module uart_tx #(
    parameter F_CLK = 100_000_000,    // 时钟频率
    parameter T_BAUD = 9600           // 波特率
)(
    input wire clk,                   // 输入时钟
    input wire rst_n,                 // 异步复位
    input wire [7:0] data_in,         // 输入数据
    input wire start,                 // 启动发送信号
    output reg tx,                    // UART 发送线
    output reg ready                  // 发送准备好信号
);

    // 计算波特率周期
    localparam PERIOD_UART = F_CLK / T_BAUD;
    
    // 位计数器宽度（8个数据位 + 1个起始位 + 1个停止位 = 10位）
    localparam BIT_COUNT_MAX = 9;  // 0-9共10位
    
    // 状态定义
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;  // 发送起始位
    localparam DATA  = 2'b10;  // 发送数据位
    localparam STOP  = 2'b11;  // 发送停止位
    
    reg [1:0] state, next_state;
    reg [7:0] tx_buffer;              // 数据缓冲寄存器
    reg [3:0] bit_count;              // 位计数器（0-9）
    reg [31:0] baud_counter;          // 波特率计数器
    
    // 位计时结束标志
    wire bit_done = (baud_counter == PERIOD_UART - 1);

    // 状态机更新
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 波特率计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= 0;
        end else begin
            if (state == IDLE) begin
                baud_counter <= 0;
            end else begin
                if (baud_counter == PERIOD_UART - 1) begin
                    baud_counter <= 0;
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end
        end
    end

    // 位计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_count <= 0;
        end else begin
            if (state == IDLE) begin
                bit_count <= 0;
            end else if (state == DATA && bit_done) begin
                if (bit_count == 7) begin
                    bit_count <= 0;  // 数据位发完，准备发停止位
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
        end
    end

    // 状态转移逻辑
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start && ready) begin
                    next_state = START;
                end
            end
            
            START: begin
                if (bit_done) begin
                    next_state = DATA;
                end
            end
            
            DATA: begin
                if (bit_done && bit_count == 7) begin
                    next_state = STOP;
                end
            end
            
            STOP: begin
                if (bit_done) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // 数据缓冲
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_buffer <= 8'b0;
        end else if (start && ready) begin
            tx_buffer <= data_in;
        end
    end

    // 输出控制
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx <= 1'b1;
            ready <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;     // 空闲状态为高电平
                    ready <= 1'b1;  // 准备好接收新数据
                end
                
                START: begin
                    tx <= 1'b0;     // 起始位为低电平
                    ready <= 1'b0;   // 忙状态
                    
                    // 在起始位结束时加载数据
                    if (bit_done) begin
                        tx <= tx_buffer[0];  // 准备发送第一个数据位
                    end
                end
                
                DATA: begin
                    ready <= 1'b0;
                    // 发送当前数据位
                    tx <= tx_buffer[bit_count];
                end
                
                STOP: begin
                    ready <= 1'b0;
                    tx <= 1'b1;     // 停止位为高电平
                end
            endcase
        end
    end

endmodule