module top_module(
    input wire clk,        // 系统时钟
    input wire rst_n,      // 异步复位
    input wire [7:0] key_state, // 按键状态（8位）
    output wire tx,        // UART 发送线
    output wire ready      // 发送准备好信号
);

    // 设定时钟频率和波特率
    parameter F_CLK = 25_000_000;  // 系统时钟 100MHz
    parameter T_BAUD = 9600;        // 波特率 9600 bps

    // 时钟分频器：每秒钟发送一次数据
    reg [31:0] counter;
    reg start_send;

    // UART TX 模块实例化
    uart_tx #(
        .F_CLK(F_CLK),
        .T_BAUD(T_BAUD)
    ) uart_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(key_state),
        .start(start_send),
        .tx(tx),
        .ready(ready)
    );

    // 每秒钟触发一次发送信号
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            counter <= 0;
            start_send <= 0;
        end else begin
            if (counter == 80000) begin // 每秒触发
                start_send <= 1; // 启动发送
                counter <= 0;    // 计数器清零
            end else begin
                start_send <= 0; // 保持空闲状态
                counter <= counter + 1; // 计数
            end
        end
    end

endmodule
