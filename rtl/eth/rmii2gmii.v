// author:		Benjamin Smith
// create time:	2023/03/17 15:57
// edit time:	2023/03/22 16:21
// platform:	Cyclone ep4ce10f17i7, 野火 board
// module:		rmii2gmii
// function:	ETH physical layer, physical rmii to virtual gmii in same clock domain. Rmii is used on physical board,
//				and gmii is used for FPGA logic data processing, so that gmii_clk is not important.
// version:		1.0
// history:		

module	rmii2gmii (
	input	wire						sys_rst_n,
	
	input	wire						rmii_clk,						// 50 MHz
	input	wire						rmii_rxdv,
	input	wire	[1:0]				rmii_rxdata,
	output	reg							rmii_txen,
	output	wire	[1:0]				rmii_txdata,
	output	wire						rmii_rst,
	
	output	wire						gmii_clk,
	output	reg							gmii_rxdv,
	output	reg		[7:0]				gmii_rxdata,
	input	wire						gmii_txen,
	input	wire	[7:0]				gmii_txdata,
	output	reg							gmii_txbusy
);

	reg									rmii_true_rxdv;
	reg		[1:0]						rmii_true_rxdata;
	reg		[1:0]						rx_data_cnt;
	reg		[1:0]						tx_data_cnt;
	reg		[7:0]						tx_data_r;

assign		gmii_clk					= rmii_clk;
assign		rmii_rst					= 1'b1;

// receive data
always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		rmii_true_rxdv <= 1'b0;
	end else if ( !rmii_rxdv ) begin
		rmii_true_rxdv <= 1'b0;
	end else if ( rmii_rxdata == 2'b0 ) begin							// before real data come, each package has a few 0 leaded
		rmii_true_rxdv <= rmii_true_rxdv;
	end else begin
		rmii_true_rxdv <= 1'b1;
	end
end

always @ ( posedge rmii_clk ) begin
	rmii_true_rxdata <= rmii_rxdata;
end

always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		rx_data_cnt <= 2'd0;
	end else if ( rmii_true_rxdv ) begin
		rx_data_cnt <= rx_data_cnt + 2'd1;
	end else begin
		rx_data_cnt <= rx_data_cnt;
	end
end

always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		gmii_rxdv <= 1'b0;
	end else if ( rmii_rxdv && !rmii_true_rxdv ) begin					// before real data come, force bottom module to receive a few 0, return to IDLE state
		gmii_rxdv <= 1'b1;
	end else if ( rx_data_cnt == 2'd3 ) begin
		gmii_rxdv <= 1'b1;
	end else begin
		gmii_rxdv <= 1'b0;
	end
end

always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		gmii_rxdata <= 8'h0;
	end else if ( rmii_rxdv && !rmii_true_rxdv ) begin
		gmii_rxdata <= 8'h0;
	end else if ( rx_data_cnt == 2'd0 ) begin
		gmii_rxdata <= { gmii_rxdata[7:2], rmii_true_rxdata };
	end else if ( rx_data_cnt == 2'd1 ) begin
		gmii_rxdata <= { gmii_rxdata[7:4], rmii_true_rxdata, gmii_rxdata[1:0] };
	end else if ( rx_data_cnt == 2'd2 ) begin
		gmii_rxdata <= { gmii_rxdata[7:6], rmii_true_rxdata, gmii_rxdata[3:0] };
	end else if ( rx_data_cnt == 2'd3 ) begin
		gmii_rxdata <= { rmii_true_rxdata, gmii_rxdata[5:0] };
	end else begin
		gmii_rxdata <= gmii_rxdata;
	end
end

// transform data
always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		tx_data_cnt <= 2'd0;
	end else if ( gmii_txen && !gmii_txbusy ) begin
		tx_data_cnt <= 2'd1;
	end else if ( tx_data_cnt >= 2'd1 ) begin
		tx_data_cnt <= tx_data_cnt + 2'd1;
	end else begin
		tx_data_cnt <= tx_data_cnt;
	end
end

always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		gmii_txbusy <= 1'b0;
	end else if ( gmii_txen && !gmii_txbusy ) begin
		gmii_txbusy <= 1'b1;
	end else if ( tx_data_cnt == 2'd3 ) begin
		gmii_txbusy <= 1'b0;
	end else begin
		gmii_txbusy <= gmii_txbusy;
	end
end

always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		rmii_txen <= 1'b0;
	end else if ( gmii_txen && !gmii_txbusy ) begin
		rmii_txen <= 1'b1;
	end else if ( !gmii_txbusy ) begin
		rmii_txen <= 1'b0;
	end else begin
		rmii_txen <= rmii_txen;
	end
end

always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		tx_data_r <= 8'h0;
	end else if ( gmii_txen && !gmii_txbusy ) begin
		tx_data_r <= gmii_txdata;
	end else begin
		tx_data_r <= tx_data_r;
	end
end

assign	rmii_txdata	=	( tx_data_cnt == 2'd1 ) ? tx_data_r[1:0] :
						( tx_data_cnt == 2'd2 ) ? tx_data_r[3:2] :
						( tx_data_cnt == 2'd3 ) ? tx_data_r[5:4] : tx_data_r[7:6];

endmodule