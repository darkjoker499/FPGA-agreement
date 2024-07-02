/*FLASH驱动模块*/
module flash_drive
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


    /************   SPI interface     *************/
    output  [P_OP_LEN - 1 : 0]          o_spi_op_data      ,   //spi操作数据，最多为指令8bit+操作地址24bit；比如读FLASH数据指令，操作数据包括03h的指令(8bit)，以及24bit的地址
    output  [1:0]                       o_spi_op_type      ,   //spi操作类型，其他指令 0 、读 1 、写 2
    output  [15:0]                      o_spi_op_len       ,   //spi操作数据长度，32bit或者8bit
    output  [15:0]                      o_spi_sclk_len     ,   //spi时钟周期，有些指令需要更长的SCLK周期才能操作完成    

    output                              o_spi_valid        ,   //spi有效信号
    input                               i_spi_ready        ,   //spi就绪信号

    output  [P_DATA_WIDTH - 1 :0]       o_spi_write_data   ,   //FPGA写入FLASH的数据       
    input                               i_spi_write_req    ,   //写数据进FLASH的请求   

    input   [P_DATA_WIDTH - 1 :0]       i_spi_read_data    ,   //FPGA从FLASH读出的数据      
    input                               i_spi_read_valid       //FLASH读数据有效       

);

/************ localparam_define *************/
    localparam                          P_OP_TYPE_READ      =   1 ;     //读指令
    localparam                          P_OP_TYPE_WRITE     =   2 ;     //写指令(页编程)
    localparam                          P_OP_TYPE_OTHER     =   3 ;     //其他指令


    localparam                          P_STATE_IDLE        =   11'b000_0000_0001;   //初始状态
    localparam                          P_STATE_ACTIVATE    =   11'b000_0000_0010;   //激活状态
    localparam                          P_STATE_WRITE_EN    =   11'b000_0000_0100;   //写使能06h
    localparam                          P_STATE_WRITE_INS   =   11'b000_0000_1000;   //写指令(页编程)02h
    localparam                          P_STATE_WRITE_DATA  =   11'b000_0001_0000;   //写数据
    localparam                          P_STATE_READ_INS    =   11'b000_0010_0000;   //读指令03h
    localparam                          P_STATE_READ_DATA   =   11'b000_0100_0000;   //读数据
    localparam                          P_STATE_ERASE       =   11'b000_1000_0000;   //擦除数据20h
    localparam                          P_STATE_BUSY        =   11'b001_0000_0000;   //忙状态
    localparam                          P_STATE_BUSY_CHECK  =   11'b010_0000_0000;   //忙检查状态(读状态寄存器)05h
    localparam                          P_STATE_BUSY_WAIT   =   11'b100_0000_0000;   //忙等待状态


/************   wire_define     *************/
    wire                                w_op_activate       ;   //用户握手激活信号开始进行一次传输
    wire                                w_spi_activate      ;   //spi激活信号

    wire     [P_DATA_WIDTH-1:0]         w_read_data         ;   //读数据,连接read_fifo

    wire                                w_write_fifo_empty  ;   //写fifo空信号
    wire                                w_write_fifo_full   ;   //写fifo满信号

    wire                                w_read_fifo_empty   ;   //读fifo空信号
    wire                                w_read_fifo_full    ;   //读fifo满信号

/************   reg_define      *************/

    /*状态机*/
    reg     [10:0]                      r_current_state     ;   //当前状态
    reg     [10:0]                      r_next_state        ;   //下一状态
    reg     [7:0]                       r_state_cnt         ;   //状态计数器

    /*user*/
    reg     [1:0]                       ri_op_type          ;   //操作类型  
    reg     [23:0]                      ri_op_addr          ;   //操作地址
    reg     [8:0]                       ri_op_byte_num      ;   //操作字节数

    reg                                 ro_op_ready         ;   //操作准备信号

    reg     [P_DATA_WIDTH-1:0]          ri_write_data       ;   //写数据
    reg                                 ri_write_sop        ;   //写数据开始信号
    reg                                 ri_write_eop        ;   //写数据结束信号
    reg                                 ri_write_valid      ;   //写数据有效信号

    reg     [P_DATA_WIDTH-1:0]          ro_read_data        ;   //读数据
    reg                                 ro_read_sop         ;   //读数据开始信号
    reg                                 ro_read_eop         ;   //读数据结束信号
    reg                                 ro_read_valid       ;   //读数据有效信号

    /*spi*/
    reg     [P_OP_LEN - 1 : 0]          ro_spi_op_data      ;   //spi操作数据
    reg     [1:0]                       ro_spi_op_type      ;   //spi操作类型
    reg     [15:0]                      ro_spi_op_len       ;   //spi操作数据长度
    reg     [15:0]                      ro_spi_sclk_len     ;   //spi时钟周期

    reg                                 ro_spi_valid        ;   //spi有效信号

    reg     [P_DATA_WIDTH - 1 :0]       ri_spi_read_data    ;   //FPGA从FLASH读出的数据
    reg                                 ri_spi_read_valid   ;   //FLASH读数据有效   

    
    /*fifo*/
    reg                                 r_read_fifo_wren        ;   //读fifo写使能               
    reg                                 r_read_fifo_rden        ;   //读fifo读使能

    reg                                 r_read_fifo_rden_d1     ;   //读fifo读使能打一拍
    reg                                 r_read_fifo_empty_d1    ;   //读fifo空信号打一拍


/************   instantiation   *************/
/*写FLASH数据fifo*/
FLASH_FIFO_8x256    u0_FLASH_FIFO_8x256_write 
(
    .clk        (i_clk              ),      
    .srst       (i_rst              ),      
    .din        (ri_write_data      ),      //要写入FLASH的数据
    .wr_en      (ri_write_valid     ),      //写入FLASH的数据有效信号为write_fifo的写使能      
    .rd_en      (i_spi_write_req    ),      //SPI数据写请求为write_fifo的读使能
    .dout       (o_spi_write_data   ),      
    .full       (w_write_fifo_full  ),      
    .empty      (w_write_fifo_empty )       
  );


/*读FLASH数据fifo*/
FLASH_FIFO_8x256    u1_FLASH_FIFO_8x256_read 
(
    .clk        (i_clk              ),      
    .srst       (i_rst              ),      
    .din        (ri_spi_read_data   ),      //从FLASH读出的数据写入read_fifo中      
    .wr_en      (r_read_fifo_wren   ),      //FLASH读出的数据有效为read_fifo的写使能
    .rd_en      (r_read_fifo_rden   ),      //read_fifo的读使能      
    .dout       (w_read_data        ),      //FLASH读出的数据      
    .full       (w_read_fifo_full   ),     
    .empty      (w_read_fifo_empty  )      
);

/************   assign_block    *************/
    assign  w_op_activate   =   i_op_valid    &&  o_op_ready    ;
    assign  w_spi_activate  =   o_spi_valid   &&  i_spi_ready   ;

    assign  o_op_ready      =   ro_op_ready                     ;
    
    assign  o_read_data     =   ro_read_data                    ;

    assign  o_read_sop      =   ro_read_sop                     ; 
    assign  o_read_eop      =   ro_read_eop                     ; 
    assign  o_read_valid    =   ro_read_valid                   ; 

    assign  o_spi_op_data   =   ro_spi_op_data                  ;
    assign  o_spi_op_type   =   ro_spi_op_type                  ;
    assign  o_spi_op_len    =   ro_spi_op_len                   ;
    assign  o_spi_sclk_len  =   ro_spi_sclk_len                 ;

    assign  o_spi_valid     =   ro_spi_valid                    ;

/************   always_block    *************/

/*三段式状态机*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_current_state <= P_STATE_IDLE;
            end
        else
            begin
                r_current_state <= r_next_state;
            end 
    end

/*busy wait状态计数器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_state_cnt <= 'd0;
            end
        else if(r_next_state == 255)
            begin
                r_state_cnt <= 'd0;
            end
        else if(((r_next_state == P_STATE_BUSY_WAIT) && (r_current_state != P_STATE_BUSY_WAIT)) || (r_state_cnt))
            begin
                r_state_cnt <= r_state_cnt + 1'b1;
            end
        else
            begin
                r_state_cnt <= r_state_cnt;
            end
    end


always@(*)
    begin
        case (r_current_state)
        P_STATE_IDLE        :   r_next_state = (w_op_activate) ? P_STATE_ACTIVATE : P_STATE_IDLE;
                                //用户握手成功一次激活成功，开始进行对FLASH的数据传输

        P_STATE_ACTIVATE    :   r_next_state = (ri_op_type == P_OP_TYPE_READ) ? 
                                P_STATE_READ_INS : P_STATE_WRITE_EN;
                                //传输被激活的时候，如果是操作类型是读，则进入读指令状态，否则进入写失能状态

        P_STATE_WRITE_EN    :   r_next_state = (w_spi_activate) ? (ri_op_type == P_OP_TYPE_WRITE
                                ? P_STATE_WRITE_INS :P_STATE_ERASE) 
                                : P_STATE_WRITE_EN;
                                //擦除指令和写数据都需要打开写使能才能进行

        P_STATE_WRITE_INS   :   r_next_state = (w_spi_activate) ? P_STATE_WRITE_DATA : P_STATE_WRITE_INS;
                                //SPI激活成功，开始写入数据
       
        P_STATE_WRITE_DATA  :   r_next_state = (i_spi_ready) ? P_STATE_BUSY  : P_STATE_WRITE_DATA  ;
                                //spi ready拉高，SPI传输完写数据之后

        P_STATE_READ_INS    :   r_next_state = (w_spi_activate) ? P_STATE_READ_DATA : P_STATE_READ_INS  ;
                                //SPI激活成功，开始传输读指令

        P_STATE_READ_DATA   :   r_next_state = (i_spi_ready) ? P_STATE_BUSY : P_STATE_READ_DATA;
                                //spi ready拉高，SPI传输完读数据之后

        P_STATE_ERASE       :   r_next_state = (w_spi_activate) ? P_STATE_BUSY  : P_STATE_ERASE  ;
                                //SPI激活成功，开始传输擦除指令
        
        P_STATE_BUSY        :   r_next_state = (w_spi_activate) ? P_STATE_BUSY_CHECK : P_STATE_BUSY  ;
                                //SPI激活成功，进入读寄存器是否繁忙状态

        P_STATE_BUSY_CHECK  :   r_next_state = (ri_spi_read_valid) ? ((i_spi_read_data[0] == 1) ? P_STATE_BUSY_WAIT : P_STATE_IDLE) : P_STATE_BUSY_CHECK;
                                //当spi读出的状态寄存器数据有效时，且读出1byte状态寄存器的[0]位为1时，说明正处于忙碌状态
                                //如果不再忙碌就进入空闲状态

        P_STATE_BUSY_WAIT   :   r_next_state = (r_state_cnt == 255) ? P_STATE_BUSY : P_STATE_BUSY_WAIT;
                                //等待255个时钟周期，重新回到忙碌状态

        default             :   r_next_state = P_STATE_IDLE; 
        endcase
    end


always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_spi_op_data  <= 'd0;
                ro_spi_op_type  <= 'd0;
                ro_spi_op_len   <= 'd0;
                ro_spi_sclk_len <= 'd0;
                ro_spi_valid    <= 'd0; 
            end
        else if(r_current_state == P_STATE_WRITE_EN)
                //FLASH 写使能命令为06h，无地址，把地址设置为0，即传输一次写使能命令为1byte数据
            begin
                ro_spi_op_data  <= {8'h06,24'd0};
                ro_spi_op_type  <= P_OP_TYPE_OTHER;
                ro_spi_op_len   <= 8;
                ro_spi_sclk_len <= 8;   //SCLK时钟为8bit 指令
                ro_spi_valid    <= 1;   //完成一次有效的spi传输
            end
        else if(r_current_state == P_STATE_WRITE_INS)
            //FLASH 写命令(页编程)为02h，24bit地址，即传输一次写使能命令为1byte+3byte数据
            begin
                ro_spi_op_data  <= {8'h02,ri_op_addr};
                ro_spi_op_type  <= P_OP_TYPE_WRITE;
                ro_spi_op_len   <= 32;
                ro_spi_sclk_len <= 32 + 8 * ri_op_byte_num; //SCLK时钟为32bit 指令+地址，还有要传输的ri_op_byte_num个数据
                ro_spi_valid    <= 1;   //完成一次有效的spi传输
            end
        else if(r_current_state == P_STATE_READ_INS)
            //FLASH 读命令为03h，24bit地址，即传输一次写使能命令为1byte+3byte数据
            begin
                ro_spi_op_data  <= {8'h03,ri_op_addr};
                ro_spi_op_type  <= P_OP_TYPE_READ;
                ro_spi_op_len   <= 32;
                ro_spi_sclk_len <= 32 + 8 * ri_op_byte_num; //SCLK时钟为32bit 指令+地址，还有要传输的ri_op_byte_num个数据
                ro_spi_valid    <= 1;   //完成一次有效的spi传输
            end
        else if(r_current_state == P_STATE_ERASE)
            //FLASH 擦除命令(扇区4KB块擦除)为03h，24bit地址，即传输一次写使能命令为1byte+3byte数据
            begin
                ro_spi_op_data  <= {8'h20,ri_op_addr};
                ro_spi_op_type  <= P_OP_TYPE_OTHER;
                ro_spi_op_len   <= 32;
                ro_spi_sclk_len <= 32 ; //SCLK时钟为32bit 指令+地址
                ro_spi_valid    <= 1;   //完成一次有效的spi传输
            end
        else if(r_current_state == P_STATE_BUSY)
            //FLASH 读忙状态就是读取状态寄存器命令为05h，无地址，即传输一次写使能命令为1byte数据
            begin
                ro_spi_op_data  <= {8'h05,24'd0};
                ro_spi_op_type  <= P_OP_TYPE_READ;
                ro_spi_op_len   <= 8;
                ro_spi_sclk_len <= 16 ; //SCLK时钟为16bit 指令+返回的1byte数据，这个byte数据[0]位为是否繁忙
                ro_spi_valid    <= 1;   //完成一次有效的spi传输
            end
        else
            begin
                ro_spi_op_data  <= ro_spi_op_data   ;
                ro_spi_op_type  <= ro_spi_op_type   ;
                ro_spi_op_len   <= ro_spi_op_len    ;
                ro_spi_sclk_len <= ro_spi_sclk_len  ;
                ro_spi_valid    <= 'd0              ;
            end    
    end

/*spi寄存数据*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ri_spi_read_data <= 'd0;
                ri_spi_read_valid<= 'd0;
            end
        else
            begin
                ri_spi_read_data <=i_spi_read_data ;
                ri_spi_read_valid<=i_spi_read_valid;
            end 
    end


/*FLASH读出的数据打一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_read_data <= 'd0;
            end
        else
            begin
                ro_read_data <=w_read_data ;
            end 
    end


/*传输激活，寄存数据*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ri_op_type          <= 'd0;
                ri_op_addr          <= 'd0;
                ri_op_byte_num      <= 'd0;
            end
        else if(w_op_activate)
            begin
                ri_op_type          <= i_op_type    ;
                ri_op_addr          <= i_op_addr    ;
                ri_op_byte_num      <= i_op_byte_num;
            end
        else
            begin
                ri_op_type          <= ri_op_type    ;
                ri_op_addr          <= ri_op_addr    ;
                ri_op_byte_num      <= ri_op_byte_num;
            end
    end


/*操作准备信号*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_op_ready  <= 'd1;
            end
        else if(r_next_state == P_STATE_IDLE)
            begin
                ro_op_ready  <= 'd1;    //空闲状态，拉高操作准备
            end
        else if(w_op_activate)
            begin
                ro_op_ready  <= 'd0;    //操作激活，拉低操作准备
            end
        else
            begin
                ro_op_ready  <= ro_op_ready;
            end 
    end


/*写相关数据寄存*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ri_write_data  <= 'd0;
                ri_write_sop   <= 'd0;
                ri_write_eop   <= 'd0;
                ri_write_valid <= 'd0;
            end
        else
            begin
                ri_write_data  <= i_write_data ;
                ri_write_sop   <= i_write_sop  ;
                ri_write_eop   <= i_write_eop  ;
                ri_write_valid <= i_write_valid;
            end 
    end


/*read fifo写使能*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_read_fifo_wren <= 'd0;
            end
        else if((r_current_state == P_STATE_READ_DATA))
            begin
                r_read_fifo_wren <= i_spi_read_valid ;  //读状态时，read fifo的写使能信号就是spi读数据有效
            end
        else
            begin
                r_read_fifo_wren <= 'd0;
            end
    end


/*read fifo读使能*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_read_fifo_rden <= 'd0;
            end
        else if(w_read_fifo_empty)
            begin
                r_read_fifo_rden <= 'd0;  //read_fifo为空的时候，不再读取其中的数据
            end
        else if((r_current_state == P_STATE_READ_DATA) && (r_current_state != r_next_state))
            begin
                r_read_fifo_rden <= 'd1;  //当结束读数据状态的时候，将使能拉高
            end
        else
            begin
                r_read_fifo_rden <= r_read_fifo_rden;
            end 
    end


/*r_read_fifo_rden打一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_read_fifo_rden_d1 <= 'd0;
            end
        else
            begin
                r_read_fifo_rden_d1 <= r_read_fifo_rden;
            end 
    end

/*read sop读开始标志*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_read_sop <= 'd0;
            end
        else if(r_read_fifo_rden && !r_read_fifo_rden_d1)
            begin
                ro_read_sop <= 'd1;     //检测到r_read_fifo_rden上升沿的时候读开始标志拉高
            end
        else
            begin
                ro_read_sop <= 'd0;
            end 
    end


/*read fifo 读空信号打一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_read_fifo_empty_d1 <= 'd0;
            end
        else
            begin
                r_read_fifo_empty_d1 <= w_read_fifo_empty;
            end 
    end


/*read eop 读结束标志*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_read_eop <= 'd0;
            end
        else if((w_read_fifo_empty && !r_read_fifo_empty_d1) && (ro_read_valid))
            begin
                ro_read_eop <= 'd1;     //检测到w_read_fifo_empty上升沿的时候,读结束标志拉高
            end 
        else
            begin
                ro_read_eop <= 'd0;
            end
    end

/*从FLASH读出的数据有效*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_read_valid <= 'd0;
            end
        else if(r_read_fifo_rden && !r_read_fifo_rden_d1)
            begin
                ro_read_valid <= 'd1;     //检测到r_read_fifo_rden上升沿的时候,读数据有效拉高
            end
        else if(ro_read_eop)
            begin
                ro_read_valid <= 'd0;     //检测到读结束标志的时候,读数据有效拉低
            end
        else
            begin
                ro_read_valid <= ro_read_valid;
            end 
    end


endmodule
