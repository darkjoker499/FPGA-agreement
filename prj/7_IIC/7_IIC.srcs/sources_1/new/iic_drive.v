/*IIC驱动*/
module iic_drive
(
    input                   i_clk           ,
    input                   i_rst           ,

    /*user interface*/
    input   [6:0]           i_device_addr   ,   //从机设备的器件地址  
    input                   i_op_addr_ctrl  ,   //从机设备操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit                                                
    input   [15:0]          i_op_addr       ,   //从机的操作地址,有些从机设备包括两个器件地址          
    input   [7:0]           i_op_byte_num   ,   //从机操作的字节数                                       
    input   [1:0]           i_op_type       ,   //从机本次操作的类型，页写0、顺序读1、随机读2                                 

    input                   i_op_valid      ,   //操作有效                                                                              
    output                  o_op_ready      ,   //操作准备                                                                              

    input   [7:0]           i_write_data    ,   //写入从机的数据                        
    output                  o_write_req     ,   //写入从机设备请求                                      

    output  [7:0]           o_read_data     ,   //读出从机的数据                                            
    output                  o_read_valid    ,   //读出从机数据有效                                                      

    output                  o_virtual_write ,   //随机读过程，完成虚拟写标志

    /*IIC interface*/
    inout                   io_iic_sda      ,   //IIC的数据线，输入、输出、高阻态
    output                  o_iic_scl           //IIC时钟线                         
);


/************ parameter_define  *************/
    /*状态*/
    parameter       P_ST_IDLE           =   11'b000_0000_0001 ;     //初始状态
    parameter       P_ST_START          =   11'b000_0000_0010 ;     //IIC起始状态
    parameter       P_ST_DEVICE_ADDR    =   11'b000_0000_0100 ;     //发送从机器件地址
    parameter       P_ST_ADDR1          =   11'b000_0000_1000 ;     //发送第一个操作的字地址，如果是16bit地址，这个状态发送addr[15:8]
    parameter       P_ST_ADDR2          =   11'b000_0001_0000 ;     //发送第二个操作的字地址，如果是16bit地址，这个状态发送addr[7:0]；如果是8bit，直接跳到这个状态
    parameter       P_ST_WRITE_DATA     =   11'b000_0010_0000 ;     //随机读状态     
    parameter       P_ST_READ_DATA      =   11'b000_0100_0000 ;     //写入数据
    parameter       P_ST_RANDOM_READ    =   11'b000_1000_0000 ;     //读出数据
    parameter       P_ST_WAIT           =   11'b001_0000_0000 ;     //IIC等待
    parameter       P_ST_STOP           =   11'b010_0000_0000 ;     //IIC停止
    parameter       P_ST_EMPTY          =   11'b100_0000_0000 ;     //空状态

    /*操作类型*/
    //页写0、顺序读1、随机读2
    parameter       P_OP_PAGE_WRITE     =   0;  //页写0
    parameter       P_OP_SEQ_READ       =   1;  //顺序读
    parameter       P_OP_RANDOM_READ    =   2;  //随机读

/************   wire_define     *************/
    wire                    w_op_activate   ;   //握手成功标志

    wire                    w_i_iic_sda     ;   //三态门中，作为从机传输到主机的数据

    wire                    w_byte_flag     ;   //完成1字节数据(读写数据、设备地址、操作地址)标志

/************   reg_define      *************/
    reg                     ro_op_ready             ;   //操作准备 
    reg                     ro_write_req            ;   //写入从机设备请求
    reg     [7:0]           ro_read_data            ;   //读出从机的数据 
    reg                     ro_read_valid           ;   //读出从机数据有效   

    reg     [7:0]           ri_device_addr_wl_rh    ;   //从机设备的器件地址，写低，读高位         
    reg                     ri_op_addr_ctrl         ;   //从机设备操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit                  
    reg     [15:0]          ri_op_addr              ;   //从机的操作地址,有些从机设备包括两个字地址，即16bit 
    reg     [7:0]           ri_op_byte_num          ;   //从机操作的字节数                            
    reg     [1:0]           ri_op_type              ;   //从机本次操作的类型，页写0、顺序读1、随机读2 

    reg     [7:0]           ri_write_data           ;   //写入从机的数据   

    /*状态机*/      
    reg     [10:0]          r_current_st            ;   //当前状态
    reg     [10:0]          r_next_st               ;   //下一个状态
    reg     [7:0]           r_st_cnt                ;   //状态计数器

    /*IIC相关控制信号*/     
    reg                     ro_iic_sda              ;   //IIC输出数据线
    reg                     r_iic_sda_ctrl          ;   //IIC三态门数据控制信号，1为向从设备写入数据，0为从设备读出数据

    reg                     ro_iic_scl              ;   //IIC时钟线 
    reg                     r_iic_scl_0             ;   //IIC时钟线翻转 

    reg                     r_random_read           ;   //IIC随机读取标志,随机读是先进行地址的假写
    reg     [7:0]           r_random_addr           ;   //随机读写完操作地址之后，再次写入设备地址和读指令

    reg     [7:0]           r_wr_cnt                ;   //读写字节数据计数器
    reg                     r_write_valid           ;   //写入数据有效，比写请求慢一拍

    reg                     r_slave_ack_valid       ;   //从机应答有效

    reg                     ro_virtual_write        ;   //随机读过程，虚拟写完成标准


/************   assign_block    *************/
    assign      w_op_activate   =   i_op_valid && o_op_ready;

    assign      o_op_ready      =   ro_op_ready   ;     
    assign      o_write_req     =   ro_write_req  ;     
    assign      o_read_data     =   ro_read_data  ;     
    assign      o_read_valid    =   ro_read_valid ;     
    assign      o_iic_scl       =   ro_iic_scl    ;     

    assign      w_byte_flag     =   (r_st_cnt == 8) && (r_iic_scl_0) ;

    assign      o_virtual_write =   ro_virtual_write;


    /*IIC三态门设计*/
    /*
        r_iic_sda_ctrl为0的时候，主机向从机传输数据ro_iic_sda
        r_iic_sda_ctrl为1的时候，主机使SDA保持高阻态，让从机控制SDA向主机传输数据，并由w_i_iic_sda接收
    */
    assign      io_iic_sda      =   (~r_iic_sda_ctrl ) ? ro_iic_sda : 1'bz;     //~r_iic_sda_ctrl,主机向从机输出数据，
                                                                                //否则保持高阻态，让从机向主机发送数据
    
    assign      w_i_iic_sda     =   (r_iic_sda_ctrl)   ? io_iic_sda : 1'b1;     //r_iic_sda_ctrl,从机向主机发送(输入)数据

    /*
    xilinx原语IOBUF设计三态门
    IOBUF 
    #(
        .DRIVE       (12            ),      // Specify the output drive strength
        .IBUF_LOW_PWR("TRUE"        ),      // Low Power - "TRUE", High Performance = "FALSE" 
        .IOSTANDARD  ("DEFAULT"     ),      // Specify the I/O standard
        .SLEW        ("SLOW"        )       // Specify the output slew rate
    ) 
    IOBUF_IIC 
    (
        .O          (ro_iic_sda     ),      // Buffer output
        .IO         (io_iic_sda     ),      // Buffer inout port (connect directly to top-level port)
        .I          (w_i_iic_sda    ),      // Buffer input
        .T          (r_iic_sda_ctrl )       // 3-state enable input, high=input, low=output
    );
    */


/************   always_block    *************/

/*状态机*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_current_st <= P_ST_IDLE;
            end
        else
            begin
                r_current_st <= r_next_st;
            end
    end

always@(*)
    begin
      case (r_current_st)
            P_ST_IDLE        :  
                begin
                    if(w_op_activate)
                        begin
                            r_next_st = P_ST_START;
                        end
                    else
                        begin
                            r_next_st = P_ST_IDLE;
                        end
                end

            P_ST_START       : 
                begin
                    r_next_st = P_ST_DEVICE_ADDR;
                end 
                
            P_ST_DEVICE_ADDR :
                begin 
                    if((w_byte_flag) && (w_i_iic_sda == 0))
                        begin
                            if((ri_op_type == P_OP_SEQ_READ) || (ri_op_type == P_OP_RANDOM_READ && r_random_read))
                                begin
                                    r_next_st = P_ST_READ_DATA;
                                    //如果操作类型是顺序读1；随机读2并且确认了随机读就跳转到读数据状态 
                                end
                            else    
                                begin
                                    r_next_st = (ri_op_addr_ctrl) ? P_ST_ADDR1 : P_ST_ADDR2;
                                    //如果操作地址是16bit，则跳转到操作地址1状态；否则跳转到操作地址2状态
                                end
                        end
                    else if(((w_byte_flag) && (w_i_iic_sda == 1)))
                        begin
                            r_next_st = P_ST_STOP;
                        end
                    else
                        begin
                            r_next_st = P_ST_DEVICE_ADDR;
                        end
                end

            P_ST_ADDR1    :      
                begin
                    if((w_byte_flag) && (w_i_iic_sda == 0))
                        begin
                            r_next_st = P_ST_ADDR2;
                        end
                    else if(((w_byte_flag) && (w_i_iic_sda == 1)))
                        begin
                            r_next_st = P_ST_STOP;
                        end
                    else
                        begin
                            r_next_st = P_ST_ADDR1;
                        end
                end

            P_ST_ADDR2    :
                begin
                    if((w_byte_flag) && (w_i_iic_sda == 0))
                        begin
                            if(ri_op_type == P_OP_PAGE_WRITE)
                                begin
                                    r_next_st = P_ST_WRITE_DATA;
                                    //如果操作类型是页写0，则跳转到写数据状态
                                end
                            else
                                begin
                                    r_next_st = P_ST_RANDOM_READ;
                                    //否则跳转到随机读
                                end
                        end
                    else if(((w_byte_flag) && (w_i_iic_sda == 1)))
                        begin
                            r_next_st = P_ST_STOP; 
                        end
                    else
                        begin
                            r_next_st = P_ST_ADDR2;
                        end
                end

            P_ST_WRITE_DATA  :
                begin
                    if((w_byte_flag) && (r_wr_cnt == (ri_op_byte_num - 1) ) && (w_i_iic_sda == 0))
                        begin
                            r_next_st = P_ST_WAIT;
                        end
                    else if(((w_byte_flag) && (w_i_iic_sda == 1)))
                        begin
                            r_next_st = P_ST_STOP;
                        end
                    else
                        begin
                            r_next_st = P_ST_WRITE_DATA;
                        end
                end

            P_ST_READ_DATA   :
                begin
                    if((w_byte_flag) && (r_wr_cnt == (ri_op_byte_num - 1)))
                        begin
                            r_next_st = P_ST_WAIT;
                        end
                    else
                        begin
                            r_next_st = P_ST_READ_DATA;
                        end
                end
                

            P_ST_RANDOM_READ : 
                begin
                    r_next_st = P_ST_STOP;    //跳到stop，然后重新进入IDLE，再进入写器件地址，再进入随机读
                end  

            P_ST_WAIT        :  
                begin
                    r_next_st = P_ST_STOP;
                end  

            P_ST_STOP        : 
                begin
                    if(r_st_cnt == 1)
                        begin
                            r_next_st = P_ST_EMPTY;
                        end
                    else
                        begin
                            r_next_st = P_ST_STOP;
                        end
                end      
            P_ST_EMPTY       :      r_next_st = (r_random_read) ? P_ST_START:P_ST_IDLE;    
            default          :      r_next_st = P_ST_IDLE;
      endcase
    end


/*状态计数器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_st_cnt <= 'd0;
            end 
        else if((r_current_st != r_next_st) || (ro_read_valid) || (r_write_valid))
            begin
                r_st_cnt <= 'd0;    //状态跳转、完成一字节数据读、写
            end
        else if(r_current_st == P_ST_STOP)
            begin
                r_st_cnt <= r_st_cnt + 1'b1;
            end
        else if(r_iic_scl_0)
            begin
                r_st_cnt <= r_st_cnt + 1'b1;
            end
        else
            begin
                r_st_cnt <= r_st_cnt;
            end
    end


/*操作准备*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_op_ready <= 'd1;
            end
        else if(w_op_activate)
            begin
                ro_op_ready <= 'd0; 
            end
        else if(r_current_st == P_ST_IDLE)
            begin
                ro_op_ready <= 'd1; 
            end
        else
            begin
                ro_op_ready <= ro_op_ready ; 
            end 
    end


/*数据寄存*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ri_device_addr_wl_rh    <= 'd0;
                ri_op_addr_ctrl         <= 'd0;
                ri_op_addr              <= 'd0;
                ri_op_byte_num          <= 'd0;
                ri_op_type              <= 'd0;
            end 
        else if(w_op_activate)
            begin
                ri_device_addr_wl_rh    <= (i_op_type == 1) ? {i_device_addr , 1'b1} : {i_device_addr , 1'b0} ;
                ri_op_addr_ctrl         <= i_op_addr_ctrl;
                ri_op_addr              <= i_op_addr     ;
                ri_op_byte_num          <= i_op_byte_num ;
                ri_op_type              <= i_op_type     ;
            end
        else
            begin
                ri_device_addr_wl_rh    <= ri_device_addr_wl_rh ;
                ri_op_addr_ctrl         <= ri_op_addr_ctrl      ;
                ri_op_addr              <= ri_op_addr           ;
                ri_op_byte_num          <= ri_op_byte_num       ;
                ri_op_type              <= ri_op_type           ;
            end
    end

/*随机读的器件地址和读指令*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_random_addr <= 'd0;
            end
        else if(w_op_activate)
            begin
                r_random_addr <= {i_device_addr , 1'b1};
            end
        else
            begin
                r_random_addr <= r_random_addr;
            end 
    end


/*IIC SCL时钟线*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_iic_scl <= 'd1;  //IIC SCL初始线为高电平
            end
        else if((r_current_st >= P_ST_DEVICE_ADDR) && (r_current_st <= P_ST_WAIT))
            begin
                ro_iic_scl <= ~ro_iic_scl;  //IIC SCL时钟线翻转
            end
        else
            begin
                ro_iic_scl <= 'd1;  //IIC SCL初始线为高电平
            end
    end


/*IIC SCL时钟线翻转*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_iic_scl_0 <= 'd0;
            end
        else if((r_current_st >= P_ST_DEVICE_ADDR) && (r_current_st <= P_ST_WAIT))
            begin
                r_iic_scl_0 <= ~r_iic_scl_0;
            end
        else
            begin
                r_iic_scl_0 <= 'd0; 
            end
    end


/*IIC SDA三态门使能控制*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_iic_sda_ctrl <= 'd0;
            end
        /*else if((r_st_cnt == 8) || (r_current_st == P_ST_IDLE))
            begin
                r_iic_sda_ctrl <= 'd1;  //当完成1字节数据传输，SDA进入高阻态；从机控制SDA
            end*/
        else if((r_current_st == P_ST_IDLE))
            begin
                r_iic_sda_ctrl <= 'd1;
            end
        else if(((r_st_cnt == 8)&&(r_current_st != P_ST_READ_DATA)))
            begin
                r_iic_sda_ctrl <= 'd1;  //当完成1字节数据传输，SDA进入高阻态；从机控制SDA
            end
        else if(((r_st_cnt == 8)&&(r_current_st == P_ST_READ_DATA)))
            begin
                r_iic_sda_ctrl <= 'd0;  //当完成1字节数据传输，SDA进入高阻态；从机控制SDA
            end
        else if(((r_current_st >= P_ST_START) && (r_current_st <= P_ST_WRITE_DATA)) || (r_current_st == P_ST_STOP))
          begin
              r_iic_sda_ctrl <= 'd0;  //当主机控制SDA，传输数据
          end
        else if(((r_st_cnt < 8)&&(r_current_st == P_ST_READ_DATA)))
            begin
                r_iic_sda_ctrl <= 'd1;
            end
        else
            begin
                r_iic_sda_ctrl <= r_iic_sda_ctrl;
            end 
    end


/*SDA数据控制*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_iic_sda <= 'd1;
            end
        else if(r_current_st == P_ST_START)
            begin
                ro_iic_sda <= 'd0;
            end
        else if((r_current_st == P_ST_READ_DATA) && (r_st_cnt == 8))
            begin
                ro_iic_sda <= 'd0;  //读数据主机应答
            end
        else if(r_st_cnt >= 8) 
            begin
                ro_iic_sda <= 1'bz; 
            end   
        else if(r_current_st == P_ST_DEVICE_ADDR)
            begin
                ro_iic_sda <= (r_random_read) ? (r_random_addr[7 - r_st_cnt]) : (ri_device_addr_wl_rh[7 - r_st_cnt]);
                //如果要随机读，而且已经传输完操作的地址，就在此输入设备地址和读指令
                //否则就是连续读和写操作 
            end
        else if(r_current_st == P_ST_ADDR1)
            begin
                ro_iic_sda <= ri_op_addr[15 - r_st_cnt];
            end
        else if(r_current_st == P_ST_ADDR2)
            begin
                ro_iic_sda <= ri_op_addr[7 - r_st_cnt];
            end
        else if(r_current_st == P_ST_WRITE_DATA)
            begin
                ro_iic_sda <= ri_write_data[7 - r_st_cnt];
            end
        else if(r_current_st == P_ST_STOP)
            begin
                ro_iic_sda <= 'd1;
            end
        else
            begin
                ro_iic_sda <= 'd1;
            end
    end


/*写请求信号*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_write_req <= 'd0;
            end
        else if(((r_current_st == P_ST_ADDR2) && (ri_op_type == P_OP_PAGE_WRITE) && (r_st_cnt == 7) && (r_iic_scl_0)))
            begin
                ro_write_req <= 'd1;    //写一个数据的情况
            end
        else if((r_current_st >= P_ST_ADDR2) && (ri_op_type == P_OP_PAGE_WRITE) && (r_st_cnt == 7) && (r_iic_scl_0))
            begin
                ro_write_req <= (r_wr_cnt < (ri_op_byte_num - 1)) ? 1 : 0;
                //当结束写操作地址，进入写状态时，如果写数据计数器小于操作字节数则，写请求拉高
            end
        else
            begin
                ro_write_req <= 'd0;
            end
    end


/*写数据有效信号*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_write_valid <= 'd0;
            end
        else
            begin
                r_write_valid <= ro_write_req;
            end 
    end


/*写数据寄存*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ri_write_data <= 'd0;
            end
        else if(r_write_valid)
            begin
                ri_write_data <= i_write_data;
            end
        else
            begin
                ri_write_data <= ri_write_data;
            end
    end


/*读写数据字节计数器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_wr_cnt <= 'd0;
            end
        else if(r_current_st == P_ST_IDLE)
            begin
                r_wr_cnt <= 'd0;
            end
        else if(((r_current_st == P_ST_WRITE_DATA ) || (r_current_st == P_ST_READ_DATA)) && (w_byte_flag))
            begin
                r_wr_cnt <= r_wr_cnt + 1'b1;
                //在读写状态下，每完成1字节的数据读写，就将读写计数器+1
            end
        else
            begin
                r_wr_cnt <= r_wr_cnt;
            end
    end


/*IIC读数据*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_read_data <= 'd0;
            end
        else if((r_current_st == P_ST_READ_DATA) && (r_st_cnt >= 1 && r_st_cnt <= 8) && (!r_iic_scl_0))
            begin
                ro_read_data <= {ro_read_data [6:0],w_i_iic_sda};
                //读状态时，先读取数据MSB
            end
        else
            begin
                ro_read_data <= ro_read_data;
            end
    end


/*IIC读数据有效信号*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_read_valid <= 'd0;
            end
        else if((r_current_st == P_ST_READ_DATA) && (r_st_cnt == 8) && (!r_iic_scl_0))
            begin
                ro_read_valid <= 'd1;
            end
        else
            begin
                ro_read_valid <= 'd0;
            end
    end


/*随机读标志*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_random_read <= 'd0;
            end
        else if(r_current_st == P_ST_READ_DATA)
            begin
                r_random_read <= 'd0;   //当进入读数据状态，就解除随机读
            end
        else if(r_current_st == P_ST_RANDOM_READ)
            begin
                r_random_read <= 'd1;   //当进入随机读状态，就拉高随机读标志
            end
        else
            begin
                r_random_read <= r_random_read;
            end
    end

/*随机读过程中，虚拟写完成标志*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_virtual_write <= 'd0;
            end
        else if((ri_op_type == P_OP_RANDOM_READ) && (r_current_st == P_ST_ADDR2) && (r_st_cnt == 8) && (!r_iic_scl_0))
            begin
                ro_virtual_write <= 'd1;
            end
        else
            begin
                ro_virtual_write <= 'd0;
            end
    end



endmodule
 