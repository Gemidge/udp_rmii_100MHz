// author:		Benjamin SMith
// create time:	2023/03/20 11:16
// edit time:	2023/03/22 11:03
// platform:	Cyclone ep4ce10f17i7, 野火 board
// module:		eth_rmii
// function:	Ethernet communication, including ARP and UDP, IPv4 only
// version:		0.1, test ARP function
// history:

module eth_rmii(
	input	wire						sys_rst_n,
	
	input	wire						rmii_clk,						// 50 MHz, used as system clock in all bottom modules
	input	wire						rmii_rxdv,
	input	wire	[1:0]				rmii_rxdata,
	output	wire						rmii_txen,
	output	wire	[1:0]				rmii_txdata,
	output	wire						rmii_rst,
	// user port
	output	wire						udp_rxstart,
	output	wire						udp_rxend,
	output	wire						udp_rxdv,
	output	wire	[7:0]				udp_rxdata,
	output	wire	[15:0]				udp_rxamount,					// total amount of data, including all pieces
	output	wire	[15:0]				udp_rxnum,						// the order of the received data in this package
	input	wire						udp_txstart,
	input	wire	[15:0]				udp_txamount,
	input	wire	[7:0]				udp_txdata,
	output	wire						udp_txreq,						// acknowledge that udp_txdata has been transfered
	output	wire						udp_txbusy
);

	wire								gmii_clk;
	wire								gmii_rxdv;
	wire	[7:0]						gmii_rxdata;
	wire								gmii_txen;
	wire	[7:0]						gmii_txdata;
	wire								gmii_txbusy;
	wire								arp_gmii_txen;
	wire	[7:0]						arp_gmii_txdata;
	wire								arp_working;
	wire								arp_pc_refresh;
	wire	[47:0]						arp_pc_mac;
	wire	[31:0]						arp_pc_ip;
	wire								udp_gmii_txen;
	wire	[7:0]						udp_gmii_txdata;
	
	wire	[47:0]						pc_mac_addr;
	wire	[31:0]						pc_ip_addr;
	wire	[15:0]						pc_port;
	wire	[15:0]						board_port;

rmii2gmii								u1_rmii2gmii (
	.sys_rst_n							( sys_rst_n			),
	.rmii_clk							( rmii_clk			),
	.rmii_rxdv							( rmii_rxdv			),
	.rmii_rxdata						( rmii_rxdata		),
	.rmii_txen							( rmii_txen			),
	.rmii_txdata						( rmii_txdata		),
	.rmii_rst							( rmii_rst			),
	.gmii_clk							( gmii_clk			),
	.gmii_rxdv							( gmii_rxdv			),
	.gmii_rxdata						( gmii_rxdata		),
	.gmii_txen							( gmii_txen			),
	.gmii_txdata						( gmii_txdata		),
	.gmii_txbusy						( gmii_txbusy		)
);

eth_arp_gmii							u2_eth_arp_gmii (
	.sys_clk							( gmii_clk			),
	.sys_rst_n							( sys_rst_n			),
	.gmii_rxdv							( gmii_rxdv			),
	.gmii_rxdata						( gmii_rxdata		),
	.gmii_txbusy						( gmii_txbusy		),
	.gmii_txen							( arp_gmii_txen		),
	.gmii_txdata						( arp_gmii_txdata	),
	.arp_working						( arp_working		),
	.pc_refresh							( arp_pc_refresh	),
	.pc_mac_addr						( arp_pc_mac		),
	.pc_ip_addr							( arp_pc_ip			)
);

udp_gmii_rx								u3_udp_gmii_rx (
	.sys_clk							( gmii_clk			),
	.sys_rst_n							( sys_rst_n			),
	.gmii_rxdv							( gmii_rxdv			),
	.gmii_rxdata						( gmii_rxdata		),
	.udp_rxstart						( udp_rxstart		),
	.udp_rxend							( udp_rxend			),
	.udp_rxdv							( udp_rxdv			),
	.udp_rxdata							( udp_rxdata		),
	.udp_rxamount						( udp_rxamount		),
	.udp_rxnum							( udp_rxnum			),
	.pc_mac_addr						( pc_mac_addr		),
	.pc_ip_addr							( pc_ip_addr		),
	.pc_port							( pc_port			),
	.board_port							( board_port		)
);

udp_gmii_tx								u4_udp_gmii_tx (
	.sys_clk							( gmii_clk			),
	.sys_rst_n							( sys_rst_n			),
	.gmii_txbusy						( gmii_txbusy		),
	.gmii_txen							( udp_gmii_txen		),
	.gmii_txdata						( udp_gmii_txdata	),
	.udp_txstart						( udp_txstart		),
	.udp_txamount						( udp_txamount		),
	.udp_txdata							( udp_txdata		),
	.udp_txreq							( udp_txreq			),
	.udp_txbusy							( udp_txbusy		),
	.pc_mac_addr						( pc_mac_addr		),
	.pc_ip_addr							( pc_ip_addr		),
	.pc_port							( pc_port			),
	.board_port							( board_port		)
);

assign		gmii_txdata		=	arp_working ? arp_gmii_txdata :
								udp_txbusy ? udp_gmii_txdata : 8'h0;
assign		gmii_txen		=	arp_working ? arp_gmii_txen :
								udp_txbusy ? udp_gmii_txen : 1'b0;		

endmodule