// author:		Benjamin SMith
// create time:	2023/03/22 11:07
// edit time:	2023/03/22 16:21
// platform:	Cyclone ep4ce10f17i7, 野火 board
// module:		udp_loop
// function:	UDP loop, transform information back to server
// version:		1.0
// history:	

module udp_loop (
	input	wire						sys_rst_n,
	
	input	wire						rmii_clk,
	input	wire						rmii_rxdv,
	input	wire	[1:0]				rmii_rxdata,
	output	wire						rmii_txen,
	output	wire	[1:0]				rmii_txdata,
	output	wire						rmii_rst
);

	wire								udp_rxstart;
	wire								udp_rxend;
	wire								udp_rxdv;
	wire	[7:0]						udp_rxdata;
	wire	[15:0]						udp_rxamount;
	wire	[15:0]						udp_rxnum;
	reg									udp_txstart;
	reg		[15:0]						udp_txamount;
	wire	[7:0]						udp_txdata;
	wire								udp_txreq;
	wire								udp_txbusy;

eth_rmii								u1_eth_rmii (
	.sys_rst_n							( sys_rst_n		),
	.rmii_clk							( rmii_clk		),
	.rmii_rxdv							( rmii_rxdv		),
	.rmii_rxdata						( rmii_rxdata	),
	.rmii_txen							( rmii_txen		),
	.rmii_txdata						( rmii_txdata	),
	.rmii_rst							( rmii_rst		),
	.udp_rxstart						( udp_rxstart	),
	.udp_rxend							( udp_rxend		),
	.udp_rxdv							( udp_rxdv		),
	.udp_rxdata							( udp_rxdata	),
	.udp_rxamount						( udp_rxamount	),
	.udp_rxnum							( udp_rxnum		),
	.udp_txstart						( udp_txstart	),
	.udp_txamount						( udp_txamount	),
	.udp_txdata							( udp_txdata	),
	.udp_txreq							( udp_txreq		),
	.udp_txbusy							( udp_txbusy	)
);

fifo_2048_d8							u2_fifo_2048_d8 (
	.aclr								( !sys_rst_n	),
	.clock								( rmii_clk		),
	.data								( udp_rxdata	),
	.rdreq								( udp_txreq		),
	.wrreq								( udp_rxdv		),
	.q									( udp_txdata	)
);

always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_txstart <= 1'b0;
	end else if ( udp_rxend ) begin
		udp_txstart <= 1'b1;
	end else begin
		udp_txstart <= 1'b0;
	end
end

always @ ( posedge rmii_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_txamount <= 16'd0;
	end else if ( udp_rxstart ) begin
		udp_txamount <= udp_rxamount;
	end else begin
		udp_txamount <= udp_txamount;
	end
end

endmodule