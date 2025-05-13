//?????????????????????????????????????????????????????????????????????????????
//  tetris.sv 
//           
//?????????????????????????????????????????????????????????????????????????????
`ifndef TETRIS_CORE_SV
`define TETRIS_CORE_SV

module tetris_core #(
    parameter int DROP_DIV   = 20,  
    parameter int MID_COL    = 3,
    parameter int NUM_SHAPES = 7,
    parameter int NUM_ORI    = 4,
    parameter int TOTAL_MASK = NUM_SHAPES*NUM_ORI   // 28
)(
    input  logic        Reset,
    input  logic        vsync,                 // 60?Hz pulse
    input  logic [31:0] keycodes,             
    output logic [3:0]  board [0:199],     
    output logic [2:0]  cur_shape,
    output logic [1:0]  cur_orient,
    output logic [4:0]  cur_row,
    output logic signed [5:0] cur_col,
    output logic [3:0]  cur_clr,
    output logic [15:0] score,
    output logic        game_over              // <?? NEW
);

    logic [2:0] next_shape;
    
    localparam logic [15:0] SHAPE_ROM [0:27] = '{
        16'b0000_1111_0000_0000, 16'b0010_0010_0010_0010,
        16'b0000_1111_0000_0000, 16'b0010_0010_0010_0010,
        16'b0000_0110_0110_0000, 16'b0000_0110_0110_0000,
        16'b0000_0110_0110_0000, 16'b0000_0110_0110_0000,
        16'b0000_0100_1110_0000, 16'b0000_0100_0110_0100,
        16'b0000_0000_1110_0100, 16'b0000_0100_1100_0100,
        16'b0000_0011_0110_0000, 16'b0000_0100_0110_0010,
        16'b0000_0011_0110_0000, 16'b0000_0100_0110_0010,
        16'b0000_1100_0110_0000, 16'b0000_0010_0110_0100,
        16'b0000_1100_0110_0000, 16'b0000_0010_0110_0100,
        16'b0000_1000_1110_0000, 16'b0000_0110_0100_0100,
        16'b0000_0000_1110_0010, 16'b0000_0100_0100_1100,
        16'b0000_0010_1110_0000, 16'b0000_0100_0100_0110,
        16'b0000_0000_1110_1000, 16'b0000_1100_0100_0100
    };

    localparam logic [3:0] COLOR_ROM [0:6] =
        '{4'h6,4'h4,4'h5,4'h2,4'h1,4'h3,4'h7};

    function automatic int idx(input int r,input int c); return r*10+c; endfunction

    function automatic logic has_key(input logic[31:0]kc,input logic[7:0]v);
        return (kc[7:0]==v)||(kc[15:8]==v)||(kc[23:16]==v)||(kc[31:24]==v);
    endfunction

    function automatic logic will_hit
        (input int dr,input int dc,input logic[2:0]shp,input logic[1:0]ori);
        int bp,r,c; logic[15:0] m;
        begin
            will_hit = 0; m = SHAPE_ROM[shp*NUM_ORI+ori];
            for (bp=0; bp<16; bp++)
                if (m[bp]) begin
                    r = cur_row + dr + bp/4;
                    c = cur_col + dc + bp%4;
                    if (r>19 || c<0 || c>9)        will_hit = 1;
                    else if (board[idx(r,c)] != 0) will_hit = 1;
                end
        end
    endfunction

   
    localparam int DIV_W=$clog2(DROP_DIV);
    logic[DIV_W-1:0] div_ctr; wire tick_grav=(div_ctr==DROP_DIV-1);
    always_ff @(posedge vsync or posedge Reset)
        if(Reset) div_ctr<=0; else div_ctr<=tick_grav?0:div_ctr+1;


    logic a_now,d_now,s_now,w_now,a_prev,d_prev,s_prev,w_prev;
    always_ff @(posedge vsync or posedge Reset)
        if(Reset) {a_prev,d_prev,s_prev,w_prev}<=0;
        else      {a_prev,d_prev,s_prev,w_prev}<={a_now,d_now,s_now,w_now};

    always_comb begin
        a_now = has_key(keycodes,8'h04);
        d_now = has_key(keycodes,8'h07);
        s_now = has_key(keycodes,8'h16);
        w_now = has_key(keycodes,8'h1A);
    end
    wire trig_left=a_now&~a_prev, trig_right=d_now&~d_prev;
    wire trig_soft=s_now,         trig_rot=w_now&~w_prev;

  
    logic [15:0] score_reg; assign score = score_reg;
    int bp,r,c,write_r,cleared; logic [15:0] mask;
    logic [3:0] temp_board [0:199];
    logic       spawn_blocked;   
    always_ff @(posedge vsync or posedge Reset) begin
        if (Reset) begin
            for (r=0;r<200;r++) board[r]<=0;
            cur_shape<=0;cur_orient<=0;cur_row<=0;cur_col<=MID_COL;
            cur_clr<=COLOR_ROM[0];
            score_reg<=0;
            game_over<=0;                // NEW
        end
        else if (!game_over) begin      
            
            if (trig_rot) begin
                logic[1:0] nori=(cur_orient==3)?0:cur_orient+1;
                if(!will_hit(0,0,cur_shape,nori)) cur_orient<=nori;
            end

            // ?? horizontal move ??
            if (trig_left && !will_hit(0,-1,cur_shape,cur_orient)) cur_col<=cur_col-1;
            else if (trig_right && !will_hit(0,1,cur_shape,cur_orient)) cur_col<=cur_col+1;


            if (tick_grav || trig_soft) begin
                if (will_hit(1,0,cur_shape,cur_orient)) begin
                    
                    for (r=0;r<200;r++) temp_board[r] = board[r];
                    mask = SHAPE_ROM[cur_shape*NUM_ORI+cur_orient];
                    for (bp=0; bp<16; bp++)
                        if (mask[bp]) begin
                            r = cur_row + bp/4; c = cur_col + bp%4;
                            temp_board[idx(r,c)] = cur_clr;
                        end

       
                    cleared = 0; write_r = 19;
                    for (r=19; r>=0; r--) begin
                        logic full = 1;
                        for (c=0;c<10;c++)
                            if (temp_board[idx(r,c)] == 0) full = 0;
                        if (full)
                            cleared = cleared + 1;
                        else begin
                            if (write_r != r)
                                for (c=0;c<10;c++)
                                    temp_board[idx(write_r,c)] =
                                        temp_board[idx(r,c)];
                            write_r = write_r - 1;
                        end
                    end
                    for (r=0;r<20;r++)
                        if (r <= write_r)
                            for (c=0;c<10;c++)
                                temp_board[idx(r,c)] = 0;

                    
                    for (r=0;r<200;r++) board[r] <= temp_board[r];

  
                    case(cleared)
                        1: score_reg <= (score_reg+1  >16'hFFFF)?16'hFFFF:score_reg+1;
                        2: score_reg <= (score_reg+2  >16'hFFFF)?16'hFFFF:score_reg+2;
                        3: score_reg <= (score_reg+5  >16'hFFFF)?16'hFFFF:score_reg+5;
                        4: score_reg <= (score_reg+10 >16'hFFFF)?16'hFFFF:score_reg+10;
                        default: ;
                    endcase


                    next_shape = (cur_shape==NUM_SHAPES-1)?0:cur_shape+1;

                    spawn_blocked = 0;
                    mask = SHAPE_ROM[next_shape*NUM_ORI]; 
                    for (bp=0; bp<16; bp++) if (mask[bp]) begin
                        r = 0 + bp/4;
                        c = MID_COL + bp%4;
                        if (temp_board[idx(r,c)] != 0) spawn_blocked = 1;
                    end

                    if (spawn_blocked) begin
                        game_over <= 1;           
                    end
                    else begin
                        cur_shape  <= next_shape;
                        cur_orient <= 0;
                        cur_row    <= 0;
                        cur_col    <= MID_COL;
                        cur_clr    <= COLOR_ROM[next_shape];
                    end
                end
                else begin
                    cur_row <= cur_row + 1;
                end
            end
        end
    end
endmodule
`endif



`ifndef TETRIS_RENDER_SV
`define TETRIS_RENDER_SV
//?????????????????????????????????????????????????????????????????????????????
//  tetris_render.sv 
//?????????????????????????????????????????????????????????????????????????????
module tetris_render #(
    parameter int CELL = 16,
    parameter int X0   = (640-10*CELL)/2
)(
    input  logic        game_over,     
    input  logic [9:0]  DrawX,
    input  logic [9:0]  DrawY,
    input  logic [3:0]  board [0:199],
    input  logic [2:0]  cur_shape,
    input  logic [1:0]  cur_orient,
    input  logic [4:0]  cur_row,
    input  logic signed [5:0] cur_col,
    input  logic [3:0]  cur_clr,
    output logic [3:0]  Red,
    output logic [3:0]  Green,
    output logic [3:0]  Blue
);

    localparam logic [15:0] SHAPE_ROM [0:27] = '{
        16'b0000_1111_0000_0000, 16'b0010_0010_0010_0010,
        16'b0000_1111_0000_0000, 16'b0010_0010_0010_0010,
        16'b0000_0110_0110_0000, 16'b0000_0110_0110_0000,
        16'b0000_0110_0110_0000, 16'b0000_0110_0110_0000,
        16'b0000_0100_1110_0000, 16'b0000_0100_0110_0100,
        16'b0000_0000_1110_0100, 16'b0000_0100_1100_0100,
        16'b0000_0011_0110_0000, 16'b0000_0100_0110_0010,
        16'b0000_0011_0110_0000, 16'b0000_0100_0110_0010,
        16'b0000_1100_0110_0000, 16'b0000_0010_0110_0100,
        16'b0000_1100_0110_0000, 16'b0000_0010_0110_0100,
        16'b0000_1000_1110_0000, 16'b0000_0110_0100_0100,
        16'b0000_0000_1110_0010, 16'b0000_0100_0100_1100,
        16'b0000_0010_1110_0000, 16'b0000_0100_0100_0110,
        16'b0000_0000_1110_1000, 16'b0000_1100_0100_0100
    };


    logic [4:0] row; logic signed [6:0] col; logic in_board;
    always_comb begin
        row      = DrawY / CELL;
        col      = (DrawX - X0) / CELL;
        in_board = (DrawX >= X0) && (DrawX < X0 + 10*CELL) &&
                   (DrawY < 20*CELL);
    end


    function automatic logic hits_active
        (input logic [4:0] r_in,input logic signed [6:0] c_in);
        int bp; logic [15:0] m;
        begin
            m = SHAPE_ROM[cur_shape*4+cur_orient];
            hits_active = 0;
            for (bp=0; bp<16; bp++)
                if (m[bp])
                    if (r_in==cur_row+bp/4 && c_in==cur_col+bp%4)
                        hits_active = 1;
        end
    endfunction


    logic [3:0] cell_clr = in_board ? board[row*10+col] : 4'h0;
    logic [3:0] pix_clr;
    always_comb begin
     if (!in_board)                 pix_clr = 4'h0;
    else if (hits_active(row,col)) pix_clr = cur_clr;
        else if (cell_clr == 0)        pix_clr = 4'hF;
        else                           pix_clr = cell_clr;
    end


    always_comb begin
        if (game_over) begin
            Red   = 4'd15;
            Green = 4'd0;
            Blue  = 4'd0;
        end
        else begin
            unique case (pix_clr)
                4'h0 : begin Red=0;  Green=0;  Blue=0;  end
                4'h1 : begin Red=15; Green=0;  Blue=0;  end
                4'h2 : begin Red=0;  Green=15; Blue=0;  end
                4'h3 : begin Red=0;  Green=0;  Blue=15; end
                4'h4 : begin Red=15; Green=15; Blue=0;  end
                4'h5 : begin Red=0;  Green=15; Blue=15; end
                4'h6 : begin Red=15; Green=8;  Blue=0;  end
                4'h7 : begin Red=8;  Green=8;  Blue=8;  end
                4'hF : begin Red=15; Green=15; Blue=15; end
                default: begin Red=15; Green=0; Blue=15; end
            endcase
        end
    end
endmodule
`endif
