module uart_rx #(
    parameter CLK_FREQ = 25_000_000,  // 晶振频率，默认50MHz
    parameter BAUD_RATE = 9600      // 波特率，默认115200
)(
    input wire clk,           // 系统时钟
    input wire rst,           // 异步复位，高有效
    input wire rx_en,         // 接收使能，高有效
    input wire rx_in,         // 串行输入
    output wire rx_idle,      // 空闲信号，高表示空闲
    output reg [7:0] rx_data, // 接收数据输出
    output reg rx_ready       // 数据接收完成标志
);

// ================== 参数计算 ==================
localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;      // 一个波特率周期的时钟数
localparam HALF_BAUD_DIV = BAUD_DIV / 2;         // 半个波特率周期的时钟数

// 波特率计数器宽度计算
localparam BAUD_CNT_WIDTH = $clog2(BAUD_DIV) + 1;
localparam BIT_CNT_WIDTH = 3;  // 位计数器宽度，0-7

// ================== 状态定义 ==================
localparam [1:0] IDLE  = 2'b00;  // 空闲状态
localparam [1:0] START = 2'b01;  // 起始位状态
localparam [1:0] DATA  = 2'b10;  // 数据位状态
localparam [1:0] STOP  = 2'b11;  // 停止位状态

// ================== 内部寄存器声明 ==================
reg [1:0] state_reg, state_next;           // 状态寄存器
reg [BAUD_CNT_WIDTH-1:0] half_baud_cnt;    // 半波特率计时器
reg [BAUD_CNT_WIDTH-1:0] full_baud_cnt;    // 全波特率计时器
reg [BIT_CNT_WIDTH-1:0] bit_cnt;           // 数据位计数器(0-7)
reg [7:0] rx_shift_reg;                    // 数据移位寄存器
reg rx_sync1, rx_sync2;                    // 两级同步寄存器
reg rx_prev;                               // 前一个同步值
reg half_baud_en;                          // 半波特率计时使能
reg full_baud_en;                          // 全波特率计时使能
reg [7:0] data_hold;                       // 数据保持寄存器
reg data_valid;                            // 数据有效标志
reg [7:0] output_hold;                     // 输出保持寄存器

// ================== 输入同步化 ==================
// 防止亚稳态，两级同步
always @(posedge clk or negedge  rst) begin
    if (!rst) begin
        rx_sync1 <= 1'b1;
        rx_sync2 <= 1'b1;
    end else if (rx_en) begin
        rx_sync1 <= rx_in;      // 第一级同步
        rx_sync2 <= rx_sync1;   // 第二级同步
    end else begin
        rx_sync1 <= 1'b1;
        rx_sync2 <= 1'b1;
    end
end

// ================== 下降沿检测寄存器 ==================
always @(posedge clk or negedge  rst) begin
    if (!rst) begin
        rx_prev <= 1'b1;
    end else if (rx_en) begin
        rx_prev <= rx_sync2;  // 保存前一周期值
    end else begin
        rx_prev <= 1'b1;
    end
end

// 下降沿检测信号
wire rx_falling_edge = (rx_prev == 1'b1) && (rx_sync2 == 1'b0);

// ================== 状态寄存器 ==================
always @(posedge clk or negedge  rst) begin
    if (!rst) begin
        state_reg <= IDLE;
    end else if (rx_en) begin
        state_reg <= state_next;
    end else begin
        state_reg <= IDLE;  // 接收使能无效时强制回到IDLE
    end
end

// ================== 半波特率计时器 ==================
always @(posedge clk or negedge  rst) begin
    if (!rst) begin
        half_baud_cnt <= 0;
    end else if (rx_en && state_reg == START && half_baud_en) begin
        if (half_baud_cnt >= HALF_BAUD_DIV - 1) begin
            half_baud_cnt <= 0;  // 计数满，清零
        end else begin
            half_baud_cnt <= half_baud_cnt + 1;  // 计数
        end
    end else begin
        half_baud_cnt <= 0;  // 其他情况清零
    end
end

// 半波特率计时完成标志
wire half_baud_done = (half_baud_cnt == HALF_BAUD_DIV - 1) && (state_reg == START) && half_baud_en;

// ================== 全波特率计时器 ==================
always @(posedge clk or negedge  rst) begin
    if (!rst) begin
        full_baud_cnt <= 0;
    end else if (rx_en && (state_reg == DATA || state_reg == STOP) && full_baud_en) begin
        if (full_baud_cnt >= BAUD_DIV - 1) begin
            full_baud_cnt <= 0;  // 计数满，清零
        end else begin
            full_baud_cnt <= full_baud_cnt + 1;  // 计数
        end
    end else begin
        full_baud_cnt <= 0;  // 其他情况清零
    end
end

// 全波特率计时完成标志
wire full_baud_done = (full_baud_cnt == BAUD_DIV - 1) && (state_reg == DATA || state_reg == STOP) && full_baud_en;

// ================== 数据位计数器 ==================
always @(posedge clk or negedge  rst) begin
    if (!rst) begin
        bit_cnt <= 0;
    end else if (rx_en) begin
        if (state_reg == DATA && full_baud_done) begin
            if (bit_cnt == 3'd7) begin
                bit_cnt <= 0;  // 计数到7后清零
            end else begin
                bit_cnt <= bit_cnt + 1;  // 计数
            end
        end else if (state_reg != DATA) begin
            bit_cnt <= 0;  // 不在DATA状态时清零
        end
    end else begin
        bit_cnt <= 0;  // 接收使能无效时清零
    end
end

// 数据位计数完成标志
wire bit_cnt_done = (bit_cnt == 3'd7) && full_baud_done && (state_reg == DATA);

// ================== 状态转移逻辑 ==================
always @(*) begin
    // 默认值
    state_next = state_reg;
    half_baud_en = 1'b0;
    full_baud_en = 1'b0;
    
    case (state_reg)
        IDLE: begin
            // 在IDLE状态，检测下降沿
            if (rx_falling_edge) begin
                state_next = START;       // 检测到下降沿，进入START状态
                half_baud_en = 1'b1;      // 使能半波特率计时器
            end
        end
        
        START: begin
            half_baud_en = 1'b1;  // 使能半波特率计时器
            
            if (half_baud_done) begin
                if (rx_sync2 == 1'b0) begin
                    // 验证起始位为低电平
                    state_next = DATA;        // 进入DATA状态
                    full_baud_en = 1'b1;      // 使能全波特率计时器
                end else begin
                    // 起始位验证失败，返回IDLE
                    state_next = IDLE;
                end
            end
        end
        
        DATA: begin
            full_baud_en = 1'b1;  // 使能全波特率计时器
            
            if (bit_cnt_done) begin
                // 接收到第8位，进入STOP状态
                state_next = STOP;
            end
        end
        
        STOP: begin
            full_baud_en = 1'b1;  // 使能全波特率计时器
            
            if (full_baud_done) begin
                // 停止位接收完成，返回IDLE
                state_next = IDLE;
            end
        end
        
        default: begin
            state_next = IDLE;
        end
    endcase
    
    // 接收使能无效时强制返回IDLE
    if (!rx_en) begin
        state_next = IDLE;
    end
end

// ================== 数据移位寄存器 ==================
always @(posedge clk or negedge  rst) begin
    if (!rst) begin
        rx_shift_reg <= 8'b0;
    end else if (rx_en && state_reg == DATA && full_baud_done) begin
        // 在中点采样，右移输入数据
        rx_shift_reg <= {rx_sync2, rx_shift_reg[7:1]};
    end
end

// ================== 数据保持寄存器 ==================
// 在STOP状态结束时锁存数据
always @(posedge clk or negedge  rst) begin
    if (!rst) begin
        data_hold <= 8'b0;
        data_valid <= 1'b0;
    end else if (rx_en && state_reg == STOP && full_baud_done) begin
        // 接收完成时锁存数据
        data_hold <= rx_shift_reg;
        data_valid <= 1'b1;
    end else begin
        data_valid <= 1'b0;
    end
end

// ================== 空闲信号生成 ==================
// 组合逻辑生成空闲信号
assign rx_idle = (state_reg == IDLE) && rx_en;

// ================== 输出保持寄存器 ==================
// 输出数据保持逻辑
always @(posedge clk or negedge  rst) begin
    if (!rst) begin
        output_hold <= 8'b0;
    end else if (rx_en) begin
        if (data_valid) begin
            // 数据就绪时更新输出保持
            output_hold <= data_hold;
        end
        // 正在读取时，保持上一次结果
    end else begin
        output_hold <= 8'b0;  // 接收使能无效时清零
    end
end

// ================== 数据输出 ==================
always @(posedge clk) begin
    if (rx_en) begin
        rx_data <= output_hold;  // 输出保持的数据
    end else begin
        rx_data <= 8'b0;  // 接收使能无效时清零输出
    end
end

// ================== 接收完成标志输出 ==================
always @(posedge clk) begin
    if (rx_en) begin
        // 数据就绪标志持续一个时钟周期
        rx_ready <= data_valid;
    end else begin
        rx_ready <= 1'b0;  // 接收使能无效时清零标志
    end
end

endmodule