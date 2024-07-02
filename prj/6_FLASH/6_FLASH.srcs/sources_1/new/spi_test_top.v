/*spi测试顶层模块*/
module spi_test_top
#(
    parameter                           P_DATA_WIDTH    = 8    ,   //接发数据的位宽  
    parameter                           P_OP_LEN        = 32   ,   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    parameter                           P_SPI_CPOL      = 0    ,   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    parameter                           P_SPI_CPHA      = 0        //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据
)
(
    input       i_clk               , 
    output      o_spi_clk           ,   //SPI时钟，由主设备(FPGA)产生
    output      o_spi_cs            ,   //SPI片选信号，由主设备(FPGA)控制，低电平有效
    output      o_spi_mosi          ,   //SPI主设备数据输出，master output slave input
    input       i_spi_miso              //SPI从设备数据输入，master input slave output       
);


/************   wire_define     *************/

wire                                w_spi_drive_clk_5MHz;
wire                                w_pll_5MHz_locked   ;   //低电平复位
wire                                w_spi_rst           ;

wire    [1:0]                       w_op_type           ;   //op：operation。操作类型，其他指令 0 、读 1 、写 2                      
wire    [23:0]                      w_op_addr           ;   //操作地址，addr[7:0]是字节地址，addr[15:8]是扇区地址，addr[23:16]是块地
wire    [8:0]                       w_op_byte_num       ;   //操作字节数，一次最多256个字节

wire                                w_op_valid          ;   //操作有效信号
wire                                w_op_ready          ;   //操作准备信号

wire    [P_DATA_WIDTH-1:0]          w_write_data        ;   //写数据
wire                                w_write_valid       ;   //写数据有效信号，此次写入的数据为有效的
wire                                w_write_sop         ;   //写数据开始信号，start
wire                                w_write_eop         ;   //写数据结束信号，end

wire    [P_DATA_WIDTH-1:0]          w_read_data         ;   //读数据
wire                                w_read_valid        ;   //读数据有效信号，此次读出的数据为有效的 
wire                                w_read_sop          ;   //写数据开始信号，start
wire                                w_read_eop          ;   //写数据结束信号，end

/************   instantiation   *************/
/*生成spi驱动时钟*/
spi_drive_5MHz  u0_spi_drive_5MHz
(
    .clk_out1   (w_spi_drive_clk_5MHz   ),     
    .locked     (w_pll_5MHz_locked      ),       
    .clk_in1    (i_clk                  )       
);



/*FLASH控制模块*/
flash_ctrl
#(
    .P_DATA_WIDTH   (P_DATA_WIDTH),   //接发数据的位宽  
    .P_OP_LEN       (P_OP_LEN    ),   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    .P_SPI_CPOL     (P_SPI_CPOL  ),   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    .P_SPI_CPHA     (P_SPI_CPHA  )    //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据
)
u1_flash_ctrl
(
    .i_clk          (w_spi_drive_clk_5MHz)               ,
    .i_rst          (w_spi_rst   )               ,

    /************   user interface     *************/
    .i_op_type      (w_op_type     )      ,   //op：operation。操作类型，其他指令 0 、读 1 、写 2                                               
    .i_op_addr      (w_op_addr     )      ,   //操作地址，addr[7:0]是字节地址，addr[15:8]是扇区地址，addr[23:16]是块地址
    .i_op_byte_num  (w_op_byte_num )      ,   //操作字节数，一次最多256个字节

    .i_op_valid     (w_op_valid    )      ,   //操作有效信号
    .o_op_ready     (w_op_ready    )      ,   //操作准备信号

    .i_write_data   (w_write_data  )      ,   //写数据
    .i_write_sop    (w_write_sop  )       ,   //写数据开始信号，start
    .i_write_eop    (w_write_eop  )       ,   //写数据结束信号，end   
    .i_write_valid  (w_write_valid )      ,   //写数据有效信号，此次写入的数据为有效的

    .o_read_data    (w_read_data   )      ,   //读数据
    .o_read_sop     (w_read_sop   )       ,   //读数据开始信号，start
    .o_read_eop     (w_read_eop   )       ,   //读数据结束信号，end   
    .o_read_valid   (w_read_valid  )      ,   //读数据有效信号，此次读出的数据为有效的

    .o_spi_clk      (o_spi_clk  )          ,   //SPI时钟，由主设备(FPGA)产生
    .o_spi_cs       (o_spi_cs   )          ,   //SPI片选信号，由主设备(FPGA)控制，低电平有效
    .o_spi_mosi     (o_spi_mosi )          ,   //SPI主设备数据输出，master output slave input
    .i_spi_miso     (i_spi_miso )              //SPI从设备数据输入，master input slave output       
);


/*生成测试数据模块*/
spi_gen_data_test
#(
    .P_DATA_WIDTH   (P_DATA_WIDTH),   //接发数据的位宽  
    .P_OP_LEN       (P_OP_LEN    ),   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    .P_SPI_CPOL     (P_SPI_CPOL  ),   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    .P_SPI_CPHA     (P_SPI_CPHA  )    //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据
)
u2_spi_gen_data_test
(
    .i_clk          (w_spi_drive_clk_5MHz)               ,
    .i_rst          (w_spi_rst   )               ,
    /************   user interface     *************/
    .o_op_type    (w_op_type    )       ,   //op：operation。操作类型，其他指令 0 、读 1 、写 2                                               
    .o_op_addr    (w_op_addr    )       ,   //操作地址，addr[7:0]是字节地址，addr[15:8]是扇区地址，addr[23:16]是块地址
    .o_op_byte_num(w_op_byte_num)       ,   //操作字节数，一次最多256个字节
    .o_op_valid   (w_op_valid   )       ,   //操作有效信号
    .i_op_ready   (w_op_ready   )       ,   //操作准备信号

    .o_write_data (w_write_data )       ,   //写数据
    .o_write_sop  (w_write_sop  )       ,   //写数据开始信号，start
    .o_write_eop  (w_write_eop  )       ,   //写数据结束信号，end
    .o_write_valid(w_write_valid)           //写数据有效信号，此次写入的数据为有效的

);

ila_0 u3_ila 
(
	.clk(w_spi_drive_clk_5MHz   ), // input wire clk

	.probe0(w_write_data        ), // input wire [7:0]  probe0  
	.probe1(w_read_data         ), // input wire [7:0]  probe1 
	.probe2(w_spi_drive_clk_5MHz       ), // input wire [0:0]  probe2 
	.probe3(w_read_valid        ), // input wire [0:0]  probe3 
	.probe4(w_op_valid          ), // input wire [0:0]  probe4 
	.probe5(w_op_ready          ) // input wire [0:0]  probe5
);


STARTUPE2 STARTUPE2_inst
(
	.GTS			(0          ),
    .USRCCLKO		(o_spi_clk  ),
    .USRCCLKTS		(0          )
);


 // End of STARTUPE2_inst instantiation
              
          

/************   assign_block    *************/
assign  w_spi_rst   = ~w_pll_5MHz_locked;

endmodule
