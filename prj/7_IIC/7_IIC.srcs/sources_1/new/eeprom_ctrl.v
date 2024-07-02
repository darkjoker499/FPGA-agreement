/*EEPROM控制模块*/
module eeprom_ctrl
(
    input                   i_clk               ,
    input                   i_rst               ,

    /*EEPROM ctrl interface*/
    input   [2:0]           i_ctrl_eeprom_addr  ,   //EEPROM器件地址组成为7'b1010_xxx,xxx根据PCB硬件设计决定
    input   [15:0]          i_ctrl_op_addr      ,   //EEPROM操作地址
    input                   i_ctrl_addr_ctrl    ,   //EEPROM操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit
    input   [1:0]           i_ctrl_op_type      ,   //EEPROM操作类型，页写0、顺序读1、随机读2
    input   [7:0]           i_ctrl_op_byte_num  ,   //EEPROM操作的字节数
    input                   i_ctrl_eeprom_valid ,   //EEPROM操作有效
    output                  o_ctrl_eeprom_ready ,   //EEPROM操作准备

    input   [7:0]           i_ctrl_write_data   ,   //EEPROM写入数据
    input                   i_ctrl_write_sop    ,   //EEPRM写入数据开始
    input                   i_ctrl_write_eop    ,   //EEPRM写入数据
    input                   i_ctrl_write_valid  ,   //EEPRM写入数据有效
                        
    output  [7:0]           o_ctrl_read_data    ,   //EEPROM读出数据
    output                  o_ctrl_read_valid   ,   //EEPRM读出数据有效

    /*IIC interface*/
    output  [6:0]           o_iic_device_addr   ,   //IIC从机设备的器件地址  
    output                  o_iic_addr_ctrl     ,   //IIC从机设备操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit                                                
    output  [15:0]          o_iic_addr          ,   //IIC从机的操作地址,有些从机设备包括两个器件地址          
    output  [7:0]           o_iic_byte_num      ,   //IIC从机操作的字节数                                       
    output  [1:0]           o_iic_type          ,   //IIC从机本次操作的类型，页写0、顺序读1、随机读2                                 

    output                  o_iic_valid         ,   //IIC操作有效                                                                              
    input                   i_iic_ready         ,   //IIC操作准备 
    
    input                   i_iic_virtual_write ,   //随机读过程，完成虚拟写标志

    output  [7:0]           o_iic_write_data    ,   //IIC写入从机的数据                        
    input                   i_iic_write_req     ,   //IIC写入从机设备请求                                      

    input   [7:0]           i_iic_read_data     ,   //IIC读出从机的数据                                            
    input                   i_iic_read_valid        //IIC读出从机数据有效
);

/************ parameter_define  *************/
    parameter       P_ST_IDLE   =   5'b0_0001  ;   //空闲状态
    parameter       P_ST_WRITE  =   5'b0_0010  ;   //写状态
    parameter       P_ST_WAIT   =   5'b0_0100  ;   //等待状态
    parameter       P_ST_READ   =   5'b0_1000  ;   //读状态
    parameter       P_ST_OREAD  =   5'b1_0000  ;   //输出读数据

    /*操作类型*/
    //页写0、顺序读1、随机读2
    parameter       P_OP_PAGE_WRITE     =   0;  //页写0
    parameter       P_OP_SEQ_READ       =   1;  //顺序读
    parameter       P_OP_RANDOM_READ    =   2;  //随机读


/************   wire_define     *************/
    wire            w_eeprom_activate   ;   //EEPROM传输激活信号

    wire            w_iic_activate      ;   //IIC传输激活信号
    wire            w_iic_end           ;   //IIC传输结束信号,检测到IIC ready的上升沿作为停止信号

    /*FIFO*/
    wire            w_write_fifo_full   ;   //write fifo的full 信号
    wire            w_write_fifo_empty  ;   //write fifo的empty信号

    wire    [7:0]   w_read_fifo_rdata   ;   //read fifo的读出的数据
    wire            w_read_fifo_full    ;   //read fifo的full 信号
    wire            w_read_fifo_empty   ;   //read fifo的empty信号



/************   reg_define      *************/

    /*状态机*/
    reg     [4:0]           r_next_st               ; 
    reg     [4:0]           r_current_st            ;   

    /*EEPROM*/
    reg     [2:0]           ri_ctrl_eeprom_addr     ;   //EEPROM器件地址组成为7'b1010_xxx,xxx根据PCB硬件设计决定
    reg     [15:0]          ri_ctrl_op_addr         ;   //EEPROM操作地址
    reg                     ri_ctrl_addr_ctrl       ;   //EEPROM操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit
    reg     [1:0]           ri_ctrl_op_type         ;   //EEPROM操作类型，页写0、顺序读1、随机读2
    reg     [7:0]           ri_ctrl_op_byte_num     ;   //EEPROM操作的字节数

    reg     [7:0]           ri_ctrl_write_data      ;   //EEPROM写入数据
    reg                     ri_ctrl_write_sop       ;   //EEPRM写入数据开始
    reg                     ri_ctrl_write_eop       ;   //EEPRM写入数据
    reg                     ri_ctrl_write_valid     ;   //EEPRM写入数据有效

    reg                     ro_ctrl_eeprom_ready    ;   //EEPROM操作准备  
    reg     [7:0]           ro_ctrl_read_data       ;   //EEPROM读数据
    reg                     ro_ctrl_read_valid      ;   //EEPROM读数据有效 

    /*IIC*/
    reg     [6:0]           ro_iic_device_addr      ;   //IIC从机设备的器件地址  
    reg                     ro_iic_addr_ctrl        ;   //IIC从机设备操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit    
    reg     [15:0]          ro_iic_addr             ;   //IIC从机的操作地址,有些从机设备包括两个器件地址          
    reg     [7:0]           ro_iic_byte_num         ;   //IIC从机操作的字节数                                       
    reg     [1:0]           ro_iic_type             ;   //IIC从机本次操作的类型，页写0、顺序读1、随机读2  
    
    reg                     ro_iic_valid            ;   //IIC操作有效 

    reg                     ri_iic_ready            ;   //IIC准备信号打一拍

    reg                     ri_iic_virtual_write    ;   //随机读过程，完成虚拟写标志

    reg     [7:0]           ri_iic_read_data        ;   //IIC读出从机的数据  
    reg                     ri_iic_read_valid       ;   //IIC读出从机数据有效

    reg     [7:0]           ro_iic_write_data       ;   //IIC写入从机的数据  

    /*其他*/
    reg                     r_read_fifo_rden        ;   //reaad fifo读使能

    reg     [7:0]           r_read_cnt              ;   //读数据计数器
    


/************   instantiation   *************/

/*EEPROM写数据fifo*/

FIFO_8x1024   u0_FIFO_8x1024_WRITE
(
  .clk      (i_clk                  ),      // input wire clk
  .srst     (i_rst                  ),      // input wire srst
  .din      (ri_ctrl_write_data     ),      // input wire [7 : 0] din
  .wr_en    (ri_ctrl_write_valid    ),      // input wire wr_en
  .rd_en    (i_iic_write_req        ),      // input wire rd_en
  .dout     (o_iic_write_data       ),      // output wire [7 : 0] dout
  .full     (w_write_fifo_full      ),      // output wire full
  .empty    (w_write_fifo_empty     )       // output wire empty
); 

/*EEPROM读数据fifo*/
FIFO_8x1024    u1_FIFO_8x1024_READ
(
  .clk      (i_clk              ),      // input wire clk
  .srst     (i_rst              ),      // input wire srst
  .din      (ri_iic_read_data   ),      // input wire [7 : 0] din
  .wr_en    (ri_iic_read_valid  ),      // input wire wr_en
  .rd_en    (r_read_fifo_rden   ),      // input wire rd_en
  .dout     (w_read_fifo_rdata  ),      // output wire [7 : 0] dout
  .full     (w_read_fifo_full   ),      // output wire full
  .empty    (w_read_fifo_empty  )       // output wire empty
);


/************   assign_block    *************/
    assign  w_eeprom_activate   =   i_ctrl_eeprom_valid && o_ctrl_eeprom_ready;

    assign  w_iic_activate      =   i_iic_ready && o_iic_valid;
    assign  w_iic_end           =   i_iic_ready && (!ri_iic_ready);

    assign  o_ctrl_eeprom_ready =   ro_ctrl_eeprom_ready;

    assign  o_ctrl_read_data    =   ro_ctrl_read_data ;
    assign  o_ctrl_read_valid   =   ro_ctrl_read_valid;

    assign  o_iic_device_addr   =   ro_iic_device_addr;
    assign  o_iic_addr_ctrl     =   ro_iic_addr_ctrl  ;
    assign  o_iic_addr          =   ro_iic_addr       ;
    assign  o_iic_byte_num      =   ro_iic_byte_num   ;
    assign  o_iic_type          =   ro_iic_type       ;

    assign  o_iic_valid         =   ro_iic_valid      ;
    
    
    
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
        P_ST_IDLE:
            begin
                if(w_eeprom_activate)
                    begin
                        if(ri_ctrl_op_type == P_OP_SEQ_READ)
                            begin
                                r_next_st = P_ST_WAIT;
                            end
                        else
                            begin
                                r_next_st = P_ST_WRITE;
                            end
                    end
                else
                    begin
                        r_next_st = P_ST_IDLE;
                    end
            end


        P_ST_WRITE:
            begin
                if((ri_ctrl_op_type == P_OP_PAGE_WRITE) && (w_iic_end))     //IIC完成页写操作
                    begin
                        r_next_st = P_ST_IDLE;
                    end
                else if((ri_ctrl_op_type == P_OP_RANDOM_READ) && (ri_iic_virtual_write))    //随机读，完成虚拟写
                    begin
                        r_next_st = P_ST_READ;
                    end
                else
                    begin
                        r_next_st = P_ST_WRITE;
                    end
            end 

        P_ST_WAIT: r_next_st = P_ST_READ;

        P_ST_READ:
            begin
                if((r_read_cnt == ri_ctrl_op_byte_num - 1) && (w_iic_end))
                    begin
                        r_next_st = P_ST_OREAD;
                    end
                else
                    begin
                        r_next_st = P_ST_READ;
                    end
            end

        P_ST_OREAD: r_next_st = (w_read_fifo_empty) ? P_ST_IDLE : P_ST_OREAD;
            
        default: r_next_st = P_ST_IDLE;
      endcase
    end


/*对输入的数据进行寄存*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
              ri_ctrl_eeprom_addr <= 'd0;
              ri_ctrl_op_addr     <= 'd0;
              ri_ctrl_addr_ctrl   <= 'd0;
              ri_ctrl_op_type     <= 'd0;
              ri_ctrl_op_byte_num <= 'd0;
            end
        else if(w_eeprom_activate)
            begin
              ri_ctrl_eeprom_addr <= i_ctrl_eeprom_addr;
              ri_ctrl_op_addr     <= i_ctrl_op_addr    ;
              ri_ctrl_addr_ctrl   <= i_ctrl_addr_ctrl  ;
              ri_ctrl_op_type     <= i_ctrl_op_type    ;
              ri_ctrl_op_byte_num <= i_ctrl_op_byte_num;
            end
        else
          begin
              ri_ctrl_eeprom_addr <= ri_ctrl_eeprom_addr;
              ri_ctrl_op_addr     <= ri_ctrl_op_addr    ;
              ri_ctrl_addr_ctrl   <= ri_ctrl_addr_ctrl  ;
              ri_ctrl_op_type     <= ri_ctrl_op_type    ;
              ri_ctrl_op_byte_num <= ri_ctrl_op_byte_num;
          end 
    end

always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
              ri_ctrl_write_data  <= 'd0;
              ri_ctrl_write_sop   <= 'd0;
              ri_ctrl_write_eop   <= 'd0;
              ri_ctrl_write_valid <= 'd0;
            end
        else
            begin
              ri_ctrl_write_data  <= i_ctrl_write_data ;
              ri_ctrl_write_sop   <= i_ctrl_write_sop  ;
              ri_ctrl_write_eop   <= i_ctrl_write_eop  ;
              ri_ctrl_write_valid <= i_ctrl_write_valid;
            end 
    end


always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ri_iic_read_data  <= 'd0;
                ri_iic_read_valid <= 'd0;
            end
        else
            begin
                ri_iic_read_data  <= i_iic_read_data ;
                ri_iic_read_valid <= i_iic_read_valid;
            end 
    end


always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ri_iic_ready <= 'd0;
                ri_iic_virtual_write <= 'd0;
            end
        else
            begin
                ri_iic_ready <= i_iic_ready;
                ri_iic_virtual_write <= i_iic_virtual_write;
            end 
    end


/*IIC操作数据*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_iic_device_addr <= 'd0;
                ro_iic_addr_ctrl   <= 'd0;
                ro_iic_addr        <= 'd0;
                ro_iic_byte_num    <= 'd0;
                ro_iic_type        <= 'd0;
                ro_iic_valid       <= 'd0; 
            end 
        else if(w_eeprom_activate)
            begin
                ro_iic_device_addr <= 'd0;
                ro_iic_addr_ctrl   <= 'd0;
                ro_iic_addr        <= 'd0;
                ro_iic_byte_num    <= 'd0;
                ro_iic_type        <= 'd0;
                ro_iic_valid       <= 'd0;
            end
        else if(ri_ctrl_write_eop)
        //write eop写结束信号，就开始传输EEPROM的IIC写操作数据
            begin
                ro_iic_device_addr <= {4'b1010,ri_ctrl_eeprom_addr};
                ro_iic_addr_ctrl   <= ri_ctrl_addr_ctrl;
                ro_iic_addr        <= ri_ctrl_op_addr;
                ro_iic_byte_num    <= ri_ctrl_op_byte_num;
                ro_iic_type        <= ri_ctrl_op_type;
                ro_iic_valid       <= 1;
            end
        else if((r_next_st == P_ST_READ) && (r_current_st != P_ST_READ))
            begin
                ro_iic_device_addr <= {4'b1010,ri_ctrl_eeprom_addr};
                ro_iic_addr_ctrl   <= ri_ctrl_addr_ctrl;
                ro_iic_addr        <= ri_ctrl_op_addr;
                ro_iic_byte_num    <= ri_ctrl_op_byte_num;
                ro_iic_type        <= ri_ctrl_op_type;
                ro_iic_valid       <= 1;
            end
        else
            begin
                ro_iic_device_addr <= ro_iic_device_addr ;
                ro_iic_addr_ctrl   <= ro_iic_addr_ctrl   ;
                ro_iic_addr        <= ro_iic_addr        ;
                ro_iic_byte_num    <= ro_iic_byte_num    ;
                ro_iic_type        <= ro_iic_type        ;
                ro_iic_valid       <= ro_iic_valid       ;
            end
    end



/*EEPROM操作准备信号*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_ctrl_eeprom_ready <= 'd1;
            end
        else if(w_eeprom_activate)
            begin
                ro_ctrl_eeprom_ready <= 'd0;
            end
        else if(r_current_st == P_ST_IDLE)
            begin
                ro_ctrl_eeprom_ready <= 'd1;
            end
        else
            begin
                ro_ctrl_eeprom_ready <= ro_ctrl_eeprom_ready;
            end 
    end


/*EEPROM读出数据寄存*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_ctrl_read_data <= 'd0;
            end
        else
            begin
                ro_ctrl_read_data <= w_read_fifo_rdata;
            end 
    end


/*EEPROM读出数据有效*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_ctrl_read_valid <= 'd0;
            end
        else if(w_read_fifo_empty)
            begin
                ro_ctrl_read_valid <= 'd0;
            end
        else if(r_read_fifo_rden)
            begin
                ro_ctrl_read_valid <= 'd1;
            end
        else
            begin
                ro_ctrl_read_valid <= ro_ctrl_read_valid;
            end 
    end





/*读数据计数器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_read_cnt <= 'd0;
            end
        else if(r_current_st == P_ST_IDLE)
            begin
                r_read_cnt <= 'd0;
            end
        else if(ri_iic_read_valid && (r_current_st == P_ST_READ))
            begin
                r_read_cnt <=  r_read_cnt + 1;
            end
        else
            begin
                r_read_cnt <= r_read_cnt;
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
                r_read_fifo_rden <= 'd0;
            end
        else if((r_next_st == P_ST_OREAD) && (r_current_st != P_ST_OREAD))
            begin
                r_read_fifo_rden <= 'd1;
            end
        else
            begin
                r_read_fifo_rden <= r_read_fifo_rden;
            end
    end

endmodule
