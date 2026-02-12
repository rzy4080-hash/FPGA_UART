`timescale 1ns / 1ns

module USART_MAX_tb;

reg clk;
reg rst_n;
reg [7:0]key_state;
wire tx;
wire ready;

top_module top_module_2(
.clk(clk),        
.rst_n(rst_n),      // 异步复位
.key_state(key_state), // 按键状态（8位）
.tx(tx),        // UART 发送线
.ready(ready)      // 发送准备好信号
);

always #10 clk = ~clk;

initial begin
clk = 1;
rst_n = 0;
key_state = 8'b10010011;
#201;
rst_n = 1;
#20000000;
$finish;

end


endmodule
