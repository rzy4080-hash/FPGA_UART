`timescale 1ns / 1ns

module RX_TB;

reg clk;
reg rst;
reg rx_en;
reg rx_in;
wire rx_idle;
wire [7:0] rx_data;
wire rx_ready;


// 设定时钟频率和波特率
parameter CLK_FREQ = 25_000_000;  // 系统时钟 100MHz
parameter BAUD_RATE = 9600;        // 波特率 9600 bps

uart_rx #(
    .CLK_FREQ(CLK_FREQ),  // 晶振频率，默认50MHz
    .BAUD_RATE(BAUD_RATE)      // 波特率，默认115200
)uart_rx_1(
   .clk(clk),           // 系统时钟
   .rst(rst),           // 异步复位，高有效
   .rx_en(rx_en),         // 接收使能，高有效
   .rx_in(rx_in),         // 串行输入
   .rx_idle(rx_idle),      // 空闲信号，高表示空闲
   .rx_data(rx_data), // 接收数据输出
   .rx_ready(rx_ready)      // 数据接收完成标志
);

always #20 clk = ~clk;

initial begin
clk = 1;
rst = 0;
rx_en = 1;
rx_in = 1;
#201;
rst = 1;
#201;
#104160;
rx_in = 0;//起始位
#104160;
//////////////////01110011
rx_in = 0;
#104160
rx_in = 1;
#104160;
rx_in = 1;
#104160;
rx_in = 1;
#104160;
rx_in = 0;
#104160;
rx_in = 0;
#104160;
rx_in = 1;
#104160;
rx_in = 1;
#104160;
rx_in = 1;//停止位
#104160;
#104160;
#104160;
rx_in = 0;//起始位
#104160;
//////////////////1001001
rx_in = 1;
#104160
rx_in = 0;
#104160;
rx_in = 0;
#104160;
rx_in = 1;
#104160;
rx_in = 0;
#104160;
rx_in = 0;
#104160;
rx_in = 1;
#104160;
rx_in = 1;
#104160;
rx_in = 1;//停止位
#104160;
#104160;
$finish;

end

endmodule
