/*FLASH控制模块*/
module flash_ctrl
#(
    parameter                           P_DATA_WIDTH    = 8    ,   //接发数据的位宽  
    parameter                           P_OP_LEN        = 32   ,   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    parameter                           P_SPI_CPOL      = 0    ,   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    parameter                           P_SPI_CPHA      = 0        //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据
)
(
    input                               i_clk               ,
    input                               i_rst               ,

    /************   user interface     *************/
    input   [1:0]                       i_op_type           ,   //op：operation。操作类型，其他指令 0 、读 1 、写 2                                               
    input   [23:0]                      i_op_addr           ,   //操作地址，addr[7:0]是字节地址，addr[15:8]是扇区地址，addr[23:16]是块地址
    input   [8:0]                       i_op_byte_num       ,   //操作字节数，一次最多256个字节

    input                               i_op_valid          ,   //操作有效信号
    output                              o_op_ready          ,   //操作准备信号

    input   [P_DATA_WIDTH-1:0]          i_write_data        ,   //写数据
    input                               i_write_sop         ,   //写数据开始信号，start
    input                               i_write_eop         ,   //写数据结束信号，end  
    output                              i_write_valid       ,   //写数据有效信号，此次写入的数据为有效的

    output  [P_DATA_WIDTH-1:0]          o_read_data         ,   //读数据
    output                              o_read_sop          ,   //读数据开始信号，start
    output                              o_read_eop          ,   //读数据结束信号，end  
    output                              o_read_valid        ,   //读数据有效信号，此次读出的数据为有效的

    output                              o_spi_clk           ,   //SPI时钟，由主设备(FPGA)产生
    output                              o_spi_cs            ,   //SPI片选信号，由主设备(FPGA)控制，低电平有效
    output                              o_spi_mosi          ,   //SPI主设备数据输出，master output slave input
    input                               i_spi_miso              //SPI从设备数据输入，master input slave output       
);


/************   wire_define     *************/

    wire    [P_OP_LEN - 1 : 0]          w_spi_op_data       ;   //spi操作数据，最多为指令8bit+操作地址24bit；比如读FLASH数据指令，操作数据包括03h的指令(8bit)，以及24bit的地址
    wire    [1:0]                       w_spi_op_type       ;   //spi操作类型，其他指令 0 、读 1 、写 2       
    wire    [15:0]                      w_spi_op_len        ;   //spi操作数据长度，32bit或者8bit       
    wire    [15:0]                      w_spi_sclk_len      ;   //spi时钟周期，有些指令需要更长的SCLK周期才能操作完成       

    wire                                w_spi_valid         ;   //spi有效信号
    wire                                w_spi_ready         ;   //spi就绪信号

    wire    [P_DATA_WIDTH - 1 :0]       w_spi_write_data    ;   //FPGA写入FLASH的数据  
    wire                                w_spi_write_req     ;   //写数据进FLASH的请求  

    wire    [P_DATA_WIDTH - 1 :0]       w_spi_read_data     ;   //FPGA从FLASH读出的数据
    wire                                w_spi_read_valid    ;   //FLASH读数据有效      



/************   instantiation   *************/
/*FLASH驱动模块*/
flash_drive
#(
    .P_DATA_WIDTH   (P_DATA_WIDTH),   //接发数据的位宽  
    .P_OP_LEN       (P_OP_LEN    ),   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    .P_SPI_CPOL     (P_SPI_CPOL  ),   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    .P_SPI_CPHA     (P_SPI_CPHA  )    //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据
)
u0_flash_drive
(
    .i_clk  (i_clk )               ,
    .i_rst  (i_rst )               ,

    /************   user interface     *************/
    .i_op_type          (i_op_type    )       ,   //op：operation。操作类型，其他指令 0 、读 1 、写 2                                               
    .i_op_addr          (i_op_addr    )       ,   //操作地址，addr[7:0]是字节地址，addr[15:8]是扇区地址，addr[23:16]是块地址
    .i_op_byte_num      (i_op_byte_num)       ,   //操作字节数，一次最多256个字节
    .i_op_valid         (i_op_valid   )       ,   //操作有效信号
    .o_op_ready         (o_op_ready   )       ,   //操作准备信号

    .i_write_data       (i_write_data )       ,   //写数据
    .i_write_sop        (i_write_sop  )       ,   //写数据开始信号，start
    .i_write_eop        (i_write_eop  )       ,   //写数据结束信号，end   
    .i_write_valid      (i_write_valid)       ,   //写数据有效信号，此次写入的数据为有效的

    .o_read_data        (o_read_data  )       ,   //读数据
    .o_read_sop         (o_read_sop   )       ,   //读数据开始信号，start
    .o_read_eop         (o_read_eop   )       ,   //读数据结束信号，end       
    .o_read_valid       (o_read_valid )       ,   //读数据有效信号，此次读出的数据为有效的


    /************   SPI interface     *************/
    .o_spi_op_data      (w_spi_op_data )     ,   //spi操作数据，最多为指令8bit+操作地址24bit；比如读FLASH数据指令，操作数据包括03h的指令(8bit)，以及24bit的地址
    .o_spi_op_type      (w_spi_op_type )     ,   //spi操作类型，其他指令 0 、读 1 、写 2
    .o_spi_op_len       (w_spi_op_len  )     ,   //spi操作数据长度，32bit或者8bit
    .o_spi_sclk_len     (w_spi_sclk_len)     ,   //spi时钟周期，有些指令需要更长的SCLK周期才能操作完成    

    .o_spi_valid        (w_spi_valid     )   ,   //spi有效信号
    .i_spi_ready        (w_spi_ready     )   ,   //spi就绪信号

    .o_spi_write_data   (w_spi_write_data)   ,   //FPGA写入FLASH的数据       
    .i_spi_write_req    (w_spi_write_req )   ,   //写数据进FLASH的请求   

    .i_spi_read_data    (w_spi_read_data )   ,   //FPGA从FLASH读出的数据      
    .i_spi_read_valid   (w_spi_read_valid)       //FLASH读数据有效       

);

/*SPI驱动模块*/
spi_drive
#(
    .P_DATA_WIDTH(P_DATA_WIDTH),   //接发数据的位宽  
    .P_OP_LEN    (P_OP_LEN    ),   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    .P_SPI_CPOL  (P_SPI_CPOL  ),   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    .P_SPI_CPHA  (P_SPI_CPHA  )    //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据
)
u1_spi_drive
(
    .i_clk              (i_clk            )   ,
    .i_rst              (i_rst            )   ,

    .o_spi_clk          (o_spi_clk        )   ,   //SPI时钟，由主设备(FPGA)产生
    .o_spi_cs           (o_spi_cs         )   ,   //SPI片选信号，由主设备(FPGA)控制，低电平有效
    .o_spi_mosi         (o_spi_mosi       )   ,   //SPI主设备数据输出，master output slave input
    .i_spi_miso         (i_spi_miso       )   ,   //SPI从设备数据输入，master input slave output

    .i_user_op_data     (w_spi_op_data   )   ,   //spi操作数据，最多为指令8bit+操作地址24bit；比如读FLASH数据指令，操作数据包括03h的指令(8bit)，以及24bit的地址
    .i_user_op_type     (w_spi_op_type   )   ,   //spi操作类型，其他指令 0 、读 1 、写 2
    .i_user_op_len      (w_spi_op_len    )   ,   //spi操作数据长度，32bit或者8bit
    .i_user_sclk_len    (w_spi_sclk_len  )   ,   //spi时钟周期，有些指令需要更长的SCLK周期才能操作完成    

    .i_user_valid       (w_spi_valid     )   ,   //从机有效信号
    .o_user_ready       (w_spi_ready     )   ,   //主机就绪信号

    .i_user_write_data  (w_spi_write_data)   ,   //写入FLASH的数据       
    .o_user_write_req   (w_spi_write_req )   ,   //写数据进FLASH的请求   

    .o_user_read_data   (w_spi_read_data )   ,   //从FLASH读出的数据      
    .o_user_read_valid  (w_spi_read_valid)       //FLASH读数据有效       

);
endmodule
