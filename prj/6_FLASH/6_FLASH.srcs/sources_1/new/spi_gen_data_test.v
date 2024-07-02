/*产生用于测试的SPI传输数据*/
module spi_gen_data_test
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
    output   [1:0]                       o_op_type           ,   //op：operation。操作类型，其他指令 0 、读 1 、写 2                                               
    output   [23:0]                      o_op_addr           ,   //操作地址，addr[7:0]是字节地址，addr[15:8]是扇区地址，addr[23:16]是块地址
    output   [8:0]                       o_op_byte_num       ,   //操作字节数，一次最多256个字节
    output                               o_op_valid          ,   //操作有效信号
    input                                i_op_ready          ,   //操作准备信号

    output   [P_DATA_WIDTH-1:0]          o_write_data        ,   //写数据
    output                               o_write_sop         ,   //写数据开始信号，start
    output                               o_write_eop         ,   //写数据结束信号，end
    output                               o_write_valid           //写数据有效信号，此次写入的数据为有效的
 
);


/************ localparam_define *************/
localparam                          P_OP_TYPE_READ      =   1 ;     //读指令
localparam                          P_OP_TYPE_WRITE     =   2 ;     //写指令(页编程)
localparam                          P_OP_TYPE_ERASE     =   3 ;     //擦除指令


localparam                          P_STATE_IDLE        =   4'b0001;   //初始状态
localparam                          P_STATE_ERASE       =   4'b0010;   //擦除数据
localparam                          P_STATE_WRITE_DATA  =   4'b0100;   //写数据
localparam                          P_STATE_READ_DATA   =   4'b1000;   //读数据

localparam                          P_DATA_NUM          =   256    ;   //传输的数据个数 

/************   wire_define     *************/
    wire                            w_op_activate               ;   //用户握手激活信号开始进行一次传输


/************   reg_define      *************/
    /*状态机*/
    reg     [3:0]                   r_current_state             ;   //当前状态
    reg     [3:0]                   r_next_state                ;   //下一个状态

    /*输入输出*/
    reg     [1:0]                   ro_op_type                  ;   //op：operation。操作类型，其他指令 0 、读 1 、写 2                               
    reg     [23:0]                  ro_op_addr                  ;   //操作地址，addr[7:0]是字节地址，addr[15:8]是扇区地址，addr[23:16]是块地址
    reg     [8:0]                   ro_op_byte_num              ;   //操作字节数，一次最多256个字节
    reg                             ro_op_valid                 ;   //操作有效信号
    reg                             ri_op_ready                 ;   //操作准备信号

    reg     [P_DATA_WIDTH-1:0]      ro_write_data               ;   //写数据
    reg                             ro_write_sop                ;   //写数据开始信号，start
    reg                             ro_write_eop                ;   //写数据结束信号，end
    reg                             ro_write_valid              ;   //写数据有效信号，此次写入的数据为有效的

    /*其他*/
    reg                             r_op_activate               ;   //用户握手激活信号开始进行一次传输打一拍
    reg     [7:0]                   r_write_cnt                 ;   //写数据计数器


/************   assign_block    *************/
    assign      w_op_activate = o_op_valid && i_op_ready    ;

    assign      o_op_type     = ro_op_type                  ;
    assign      o_op_addr     = ro_op_addr                  ;
    assign      o_op_byte_num = ro_op_byte_num              ;
    assign      o_op_valid    = ro_op_valid                 ;

    assign      o_write_data  = ro_write_data               ;
    assign      o_write_sop   = ro_write_sop                ;
    assign      o_write_eop   = ro_write_eop                ;
    assign      o_write_valid = ro_write_valid              ;


/************   always_block    *************/

/*状态机*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_current_state  <=  P_STATE_IDLE        ;
            end
        else
            begin
                r_current_state  <=  r_next_state        ;
            end 
    end

always@(*)
    begin
        case (r_current_state)
            P_STATE_IDLE       :    r_next_state =  P_STATE_ERASE;
                                    //先擦除数据，再写入数据，最后再读出数据

            P_STATE_ERASE      :    r_next_state =  (i_op_ready && (!ri_op_ready)) ? P_STATE_WRITE_DATA : P_STATE_ERASE;
                                    //上一步操作完成之后会把ready信号拉高，当检测到ready信号拉高的上升沿之后跳转状态
            
            P_STATE_WRITE_DATA :    r_next_state =  (i_op_ready && (!ri_op_ready)) ? P_STATE_READ_DATA  : P_STATE_WRITE_DATA;
            P_STATE_READ_DATA  :    r_next_state =  (i_op_ready && (!ri_op_ready)) ? P_STATE_IDLE       : P_STATE_READ_DATA;
            default            :    r_next_state =  P_STATE_IDLE        ;
        endcase
    end


/*状态变化的时候，valid有效；activate握手成功拉低*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_op_valid <= 'd0;
            end
        else if(w_op_activate)
            begin
                ro_op_valid <= 'd0;     //用户握手激活信号开始进行一次传输将valid信号拉低
            end
        else if((r_current_state != P_STATE_ERASE ) && (r_current_state != r_next_state))
            begin
                ro_op_valid <= 'd1;
            end
        else if((r_current_state != P_STATE_WRITE_DATA ) && (r_current_state != r_next_state))
            begin
                ro_op_valid <= 'd1;
            end
        else if((r_current_state != P_STATE_READ_DATA ) && (r_current_state != r_next_state))
            begin
                ro_op_valid <= 'd1;
            end
        else
            begin
                ro_op_valid <= ro_op_valid;
            end   
    end


/*不同状态数据传输*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_op_type     <= 'd0;
                ro_op_addr     <= 'd0;
                ro_op_byte_num <= 'd0;
            end
        else if(r_next_state == P_STATE_ERASE)
            begin
                ro_op_type     <= P_OP_TYPE_ERASE;
                ro_op_addr     <= 24'd0/*{8'h04,8'h05,8'h0a}*/;
                ro_op_byte_num <= 'd0;
            end
        else if(r_next_state == P_STATE_WRITE_DATA)
            begin
                ro_op_type     <= P_OP_TYPE_WRITE;
                ro_op_addr     <= 24'd0/*{8'h04,8'h05,8'h0a}*/;
                ro_op_byte_num <= P_DATA_NUM;
            end
        else if(r_next_state == P_STATE_READ_DATA)
            begin
                ro_op_type     <= P_OP_TYPE_READ;
                ro_op_addr     <= 24'd0/*{8'h04,8'h05,8'h0a}*/;
                ro_op_byte_num <= P_DATA_NUM;
            end
        else
            begin
                ro_op_type     <= ro_op_type     ;
                ro_op_addr     <= ro_op_addr     ;
                ro_op_byte_num <= ro_op_byte_num ;
            end
    end


/*i_op_ready打一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ri_op_ready <= 'd0;
            end
        else
            begin
                ri_op_ready <= i_op_ready;
            end 
    end


/*握手成功信号打一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_op_activate <= 'd0;
            end
        else
            begin
                r_op_activate <= w_op_activate;
            end 
    end

/*写数据计数*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_write_cnt <= 'd0;
            end
        else if(r_write_cnt == P_DATA_NUM - 1)
            begin
                r_write_cnt <= 'd0;
            end
        else if((r_current_state == P_STATE_WRITE_DATA) && (r_op_activate || r_write_cnt))
            begin
                r_write_cnt <= r_write_cnt + 1'b1;  //当刚刚处于写数据状态或者正在写数据(打一拍原因详见wave文件夹的timegen波形图)
            end
        else
            begin
                r_write_cnt <= r_write_cnt        ;
            end
    end


/*写入测试数据*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_write_data <= 'd0;
            end
        else if((ro_write_valid) && (ro_write_data < 255))
            begin
                ro_write_data <= ro_write_data + 1'b1   ;   //写数据有效期间，且没写到最后一个数据的时候
            end
        else
            begin
                ro_write_data <= ro_write_data          ;
            end 
    end


/*写开始标志*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_write_sop <= 'd0;
            end
        else if((r_current_state == P_STATE_WRITE_DATA) && (w_op_activate))
            begin
                ro_write_sop <= 'd1;    //写数据状态开始激活时，拉高一下写开始标志
            end
        else
            begin
                ro_write_sop <= 'd0;
            end 
    end


/*写结束标志*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_write_eop <= 'd0;
            end
        else if((r_write_cnt == (P_DATA_NUM - 2)) && (ro_write_valid))
            begin
                ro_write_eop <= 'd1;    //写数据准备结束时，拉高一下写结束标志
            end
        else
            begin
                ro_write_eop <= 'd0;
            end 
    end

/*写数据有效*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_write_valid <= 'd0;
            end
        else if(ro_write_eop)
            begin
                ro_write_valid <= 'd0;    //写数据准备结束时，拉低一下写数据有效
            end
        else if((r_current_state == P_STATE_WRITE_DATA) && (w_op_activate))
            begin
                ro_write_valid <= 'd1;    //写数据状态开始激活时，拉高一下写数据有效
            end
        else
            begin
                ro_write_valid <= ro_write_valid      ;
            end 
    end

endmodule
