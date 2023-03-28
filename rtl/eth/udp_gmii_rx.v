// author:		Benjamin SMith
// create time:	2023/03/21 08:34
// edit time:	2023/03/21 16:21
// platform:	Cyclone ep4ce10f17i7, 野火 board
// module:		udp_gmii_rx
// function:	UDP received data, only IPv4 supported. fragment is supported
// version:		1.0
// history:		0.1 don't support fragment

module udp_gmii_rx (
	input	wire							sys_clk,
	input	wire							sys_rst_n,
	input	wire							gmii_rxdv,
	input	wire	[7:0]					gmii_rxdata,
	
	output	reg								udp_rxstart,
	output	reg								udp_rxend,
	output	reg								udp_rxdv,
	output	reg		[7:0]					udp_rxdata,
	output	reg		[15:0]					udp_rxamount,					// total amount of data, including all pieces
	output	reg		[15:0]					udp_rxnum,						// the order of the received data in this package
	
	output	reg		[47:0]					pc_mac_addr,
	output	reg		[31:0]					pc_ip_addr,
	output	reg		[15:0]					pc_port,
	output	reg		[15:0]					board_port
);

	parameter		BOARD_MAC_ADDR			= 48'h00_11_22_33_44_55;
	parameter		BOARD_IP_ADDR			= 32'hA9_FE_01_17;				// 169.254.1.23
	
	localparam		IDLE					= 18'h0_0001,
					SFD						= 18'h0_0002,
					MAC_ADDR				= 18'h0_0004,					// destination MAC and source MAC
					TYPE					= 18'h0_0008,					// 'h0800, only IPv4 supported
					IP_TYPE					= 18'h0_0010,					// IP version, IP header length ( *4 Byte ), service type, 'h4500
					IP_LEN					= 18'h0_0020,					// network length
					IP_ID					= 18'h0_0040,					// identification
					IP_SPLIT				= 18'h0_0080,					// flags and fragment offset
					IP_TTL					= 18'h0_0100,					// time to live, initial value is 64 or 128
					IP_PROTOCOL				= 18'h0_0200,					// UDP: 17
					IP_CHECK				= 18'h0_0400,					// IP header checksum, ignore it
					IP_ADDR					= 18'h0_0800,					// source IP address and destination IP address
					IP_FILL					= 18'h0_1000,					// when IP header length > 5, filled data shows
					UDP_PORT				= 18'h0_2000,					// source PORT and destination PORT
					UDP_LEN					= 18'h0_4000,					// udp length, ( = network length - IP header length ) if have not split
					UDP_CHECK				= 18'h0_8000,					// udp checksum, ignore it
					DATA					= 18'h1_0000,
					CRC						= 18'h2_0000;
	
	reg		[7:0]							gmii_rxdata_d;
	reg		[17:0]							state;
	
	reg		[47:0]							des_mac;
	reg		[31:0]							des_ip;
	reg		[15:0]							des_port;
	reg		[47:0]							src_mac;
	reg		[31:0]							src_ip;
	reg		[15:0]							src_port;
	reg		[5:0]							ip_header_len;
	reg		[15:0]							ip_len;
	reg		[15:0]							udp_len;
	reg		[15:0]							id;
	reg		[2:0]							flags;
	
	reg		[2:0]							cnt_pre;
	reg		[3:0]							cnt_mac_addr;
	reg										cnt_type;
	reg										cnt_ip_type;
	reg										cnt_ip_len;
	reg										cnt_ip_id;
	reg										cnt_ip_split;
	reg										cnt_ip_check;
	reg		[2:0]							cnt_ip_addr;
	reg		[1:0]							cnt_udp_port;
	reg										cnt_udp_len;
	reg										cnt_udp_check;
	reg		[1:0]							cnt_crc;
	reg		[5:0]							cnt_network;					// count network length up to 63, avoid short data in udp, complete filled data in ip header

	wire									pc_refresh;
	reg		[15:0]							cnt_data;
	reg		[15:0]							data_len;
	reg										udp_continue;					// flags[0] is assigned to it when state == CRC. indicates that next frame is continuous

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		state <= IDLE;
	end else case ( state )
		IDLE: begin
			if ( cnt_pre >= 3'd6 && gmii_rxdv && gmii_rxdata == 8'h55 ) begin
				state <= SFD;
			end else begin
				state <= IDLE;
			end
		end
		SFD: begin
			if ( gmii_rxdv && gmii_rxdata == 8'hD5 ) begin					// SFD == 'hD5
				state <= MAC_ADDR;
			end else if ( gmii_rxdv ) begin
				state <= IDLE;
			end else begin
				state <= SFD;
			end
		end
		MAC_ADDR: begin
			if ( cnt_mac_addr >= 4'd11 && gmii_rxdv ) begin
				if ( des_mac == BOARD_MAC_ADDR ) begin
					state <= TYPE;
				end else begin
					state <= IDLE;
				end
			end else begin
				state <= MAC_ADDR;
			end
		end
		TYPE: begin
			if ( cnt_type && gmii_rxdv ) begin
				if ( {gmii_rxdata_d, gmii_rxdata} == 16'h0800 ) begin		// IPv4 only, TYPE = 'h0800
					state <= IP_TYPE;
				end else begin
					state <= IDLE;
				end
			end else begin
				state <= TYPE;
			end
		end
		IP_TYPE: begin
			if ( cnt_ip_type && gmii_rxdv ) begin
				if ( gmii_rxdata_d[7:4] == 'h4 ) begin						// IPv4 only
					state <= IP_LEN;
				end else begin
					state <= IDLE;
				end
			end else begin
				state <= IP_TYPE;
			end
		end
		IP_LEN: begin
			if ( cnt_ip_len && gmii_rxdv ) begin
				state <= IP_ID;
			end else begin
				state <= IP_LEN;
			end
		end
		IP_ID: begin
			if ( cnt_ip_id && gmii_rxdv ) begin
				state <= IP_SPLIT;
			end else begin
				state <= IP_ID;
			end
		end
		IP_SPLIT: begin
			if ( cnt_ip_split && gmii_rxdv ) begin
				state <= IP_TTL;
			end else begin
				state <= IP_SPLIT;
			end
		end
		IP_TTL: begin
			if ( gmii_rxdv ) begin
				state <= IP_PROTOCOL;
			end else begin
				state <= IP_TTL;
			end
		end
		IP_PROTOCOL: begin
			if ( gmii_rxdv && gmii_rxdata == 8'd17 ) begin					// UDP only
				state <= IP_CHECK;
			end else if ( gmii_rxdv ) begin
				state <= IDLE;
			end else begin
				state <= IP_PROTOCOL;
			end
		end
		IP_CHECK: begin
			if ( cnt_ip_check && gmii_rxdv ) begin
				state <= IP_ADDR;
			end else begin
				state <= IP_CHECK;
			end
		end
		IP_ADDR: begin
			if ( cnt_ip_addr >= 3'd7 && gmii_rxdv && udp_continue && cnt_network < ip_header_len - 1 ) begin
				state <= IP_FILL;
			end else if ( cnt_ip_addr >= 3'd7 && gmii_rxdv && udp_continue ) begin
				state <= DATA;
			end else if ( cnt_ip_addr >= 3'd7 && gmii_rxdv ) begin
				state <= UDP_PORT;
			end else begin
				state <= IP_ADDR;
			end
		end
		IP_FILL: begin
			if ( cnt_network >= ip_header_len - 1 && gmii_rxdv && udp_continue ) begin
				state <= DATA;
			end else if ( cnt_network >= ip_header_len - 1 && gmii_rxdv ) begin
				state <= UDP_PORT;
			end else begin
				state <= IP_ADDR;
			end
		end
		UDP_PORT: begin
			if ( des_ip != BOARD_IP_ADDR ) begin
				state <= IDLE;
			end else if ( cnt_udp_port >= 2'd3 && gmii_rxdv ) begin
				state <= UDP_LEN;
			end else begin
				state <= UDP_PORT;
			end
		end
		UDP_LEN: begin
			if ( cnt_udp_len && gmii_rxdv ) begin
				state <= UDP_CHECK;
			end else begin
				state <= UDP_LEN;
			end
		end
		UDP_CHECK: begin
			if ( cnt_udp_check && gmii_rxdv ) begin
				state <= DATA;
			end else begin
				state <= UDP_CHECK;
			end
		end
		DATA: begin
			if ( cnt_data >= data_len - 16'd1 && gmii_rxdv && cnt_network >= 'd45 ) begin
				state <= CRC;
			end else begin
				state <= DATA;
			end
		end
		CRC: begin
			if ( cnt_crc >= 2'd3 && gmii_rxdv ) begin
				state <= IDLE;
			end else begin
				state <= CRC;
			end
		end
		default: state <= IDLE;
	endcase
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		gmii_rxdata_d <= 8'h0;
	end else if ( gmii_rxdv ) begin
		gmii_rxdata_d <= gmii_rxdata;
	end else begin
		gmii_rxdata_d <= gmii_rxdata_d;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_pre <= 3'd0;
	end else if ( state == IDLE ) begin
		if ( gmii_rxdv && gmii_rxdata == 8'h55 ) begin
			cnt_pre <= cnt_pre + 3'd1;
		end else if ( gmii_rxdv ) begin
			cnt_pre <= 3'd0;
		end else begin
			cnt_pre <= cnt_pre;
		end
	end else begin
		cnt_pre <= 3'd0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_mac_addr <= 4'd0;
	end else if ( state == MAC_ADDR ) begin
		if ( gmii_rxdv ) begin
			cnt_mac_addr <= cnt_mac_addr + 4'd1;
		end else begin
			cnt_mac_addr <= cnt_mac_addr;
		end
	end else begin
		cnt_mac_addr <= 4'd0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		des_mac <= 48'h0;
	end else if ( state == MAC_ADDR ) begin
		if ( cnt_mac_addr == 4'd0 && gmii_rxdv ) begin
			des_mac <= { gmii_rxdata, des_mac[39:0] };
		end else if ( cnt_mac_addr == 4'd1 && gmii_rxdv ) begin
			des_mac <= { des_mac[47:40], gmii_rxdata, des_mac[31:0] };
		end else if ( cnt_mac_addr == 4'd2 && gmii_rxdv ) begin
			des_mac <= { des_mac[47:32], gmii_rxdata, des_mac[23:0] };
		end else if ( cnt_mac_addr == 4'd3 && gmii_rxdv ) begin
			des_mac <= { des_mac[47:24], gmii_rxdata, des_mac[15:0] };
		end else if ( cnt_mac_addr == 4'd4 && gmii_rxdv ) begin
			des_mac <= { des_mac[47:16], gmii_rxdata, des_mac[7:0] };
		end else if ( cnt_mac_addr == 4'd5 && gmii_rxdv ) begin
			des_mac <= { des_mac[47:8], gmii_rxdata };
		end else begin
			des_mac <= des_mac;
		end
	end else begin
		des_mac <= des_mac;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		src_mac <= 48'h0;
	end else if ( state == MAC_ADDR ) begin
		if ( cnt_mac_addr == 4'd6 && gmii_rxdv ) begin
			src_mac <= { gmii_rxdata, src_mac[39:0] };
		end else if ( cnt_mac_addr == 4'd7 && gmii_rxdv ) begin
			src_mac <= { src_mac[47:40], gmii_rxdata, src_mac[31:0] };
		end else if ( cnt_mac_addr == 4'd8 && gmii_rxdv ) begin
			src_mac <= { src_mac[47:32], gmii_rxdata, src_mac[23:0] };
		end else if ( cnt_mac_addr == 4'd9 && gmii_rxdv ) begin
			src_mac <= { src_mac[47:24], gmii_rxdata, src_mac[15:0] };
		end else if ( cnt_mac_addr == 4'd10 && gmii_rxdv ) begin
			src_mac <= { src_mac[47:16], gmii_rxdata, src_mac[7:0] };
		end else if ( cnt_mac_addr == 4'd11 && gmii_rxdv ) begin
			src_mac <= { src_mac[47:8], gmii_rxdata };
		end else begin
			src_mac <= src_mac;
		end
	end else begin
		src_mac <= src_mac;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_type <= 1'b0;
	end else if ( state == TYPE ) begin
		if ( gmii_rxdv ) begin
			cnt_type <= ~cnt_type;
		end else begin
			cnt_type <= cnt_type;
		end
	end else begin
		cnt_type <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_network <= 6'd0;
	end else if ( state == IDLE || state == SFD || state == MAC_ADDR || state == TYPE || state == CRC ) begin
		cnt_network <= 6'd0;
	end else if ( cnt_network >= 6'd63 ) begin
		cnt_network <= 6'd63;
	end else if ( gmii_rxdv ) begin
		cnt_network <= cnt_network + 6'd1;
	end else begin
		cnt_network <= cnt_network;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_ip_type <= 1'b0;
	end else if ( state == IP_TYPE ) begin
		if ( gmii_rxdv ) begin
			cnt_ip_type <= ~cnt_ip_type;
		end else begin
			cnt_ip_type <= cnt_ip_type;
		end
	end else begin
		cnt_ip_type <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		ip_header_len <= 6'd0;
	end else if ( state == IP_TYPE && !cnt_ip_type && gmii_rxdv ) begin
		ip_header_len <= gmii_rxdata[3:0] << 2;
	end else begin
		ip_header_len <= ip_header_len;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_ip_len <= 1'b0;
	end else if ( state == IP_LEN ) begin
		if ( gmii_rxdv ) begin
			cnt_ip_len <= ~cnt_ip_len;
		end else begin
			cnt_ip_len <= cnt_ip_len;
		end
	end else begin
		cnt_ip_len <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		ip_len <= 16'd0;
	end else if ( state == IP_LEN ) begin
		if ( !cnt_ip_len && gmii_rxdv ) begin
			ip_len <= { gmii_rxdata, ip_len[7:0] };
		end else if ( gmii_rxdv ) begin
			ip_len <= { ip_len[15:8], gmii_rxdata };
		end else begin
			ip_len <= ip_len;
		end
	end else begin
		ip_len <= ip_len;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_ip_id <= 1'b0;
	end else if ( state == IP_ID ) begin
		if ( gmii_rxdv ) begin
			cnt_ip_id <= ~cnt_ip_id;
		end else begin
			cnt_ip_id <= cnt_ip_id;
		end
	end else begin
		cnt_ip_id <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		id <= 16'd0;
	end else if ( state == IP_ID ) begin
		if ( !cnt_ip_id && gmii_rxdv ) begin
			id <= { gmii_rxdata, id[7:0] };
		end else if ( gmii_rxdv ) begin
			id <= { id[15:8], gmii_rxdata };
		end else begin
			id <= id;
		end
	end else begin
		id <= id;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_ip_split <= 1'b0;
	end else if ( state == IP_SPLIT ) begin
		if ( gmii_rxdv ) begin
			cnt_ip_split <= ~cnt_ip_split;
		end else begin
			cnt_ip_split <= cnt_ip_split;
		end
	end else begin
		cnt_ip_split <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		flags <= 3'h0;
	end else if ( state == IP_SPLIT && !cnt_ip_split && gmii_rxdv ) begin
		flags <= gmii_rxdata[7:5];
	end else begin
		flags <= flags;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_ip_check <= 1'b0;
	end else if ( state == IP_CHECK ) begin
		if ( gmii_rxdv ) begin
			cnt_ip_check <= ~cnt_ip_check;
		end else begin
			cnt_ip_check <= cnt_ip_check;
		end
	end else begin
		cnt_ip_check <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_ip_addr <= 3'd0;
	end else if ( state == IP_ADDR ) begin
		if ( gmii_rxdv ) begin
			cnt_ip_addr <= cnt_ip_addr + 3'd1;
		end else begin
			cnt_ip_addr <= cnt_ip_addr;
		end
	end else begin
		cnt_ip_addr <= 3'd0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		src_ip <= 32'h0;
	end else if ( state == IP_ADDR ) begin
		if ( cnt_ip_addr == 3'd0 && gmii_rxdv ) begin
			src_ip <= { gmii_rxdata, src_ip[23:0] };
		end else if ( cnt_ip_addr == 3'd1 && gmii_rxdv ) begin
			src_ip <= { src_ip[31:24], gmii_rxdata, src_ip[15:0] };
		end else if ( cnt_ip_addr == 3'd2 && gmii_rxdv ) begin
			src_ip <= { src_ip[31:16], gmii_rxdata, src_ip[7:0] };
		end else if ( cnt_ip_addr == 3'd3 && gmii_rxdv ) begin
			src_ip <= { src_ip[31:8], gmii_rxdata };
		end else begin
			src_ip <= src_ip;
		end
	end else begin
		src_ip <= src_ip;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		des_ip <= 32'h0;
	end else if ( state == IP_ADDR ) begin
		if ( cnt_ip_addr == 3'd4 && gmii_rxdv ) begin
			des_ip <= { gmii_rxdata, des_ip[23:0] };
		end else if ( cnt_ip_addr == 3'd5 && gmii_rxdv ) begin
			des_ip <= { des_ip[31:24], gmii_rxdata, des_ip[15:0] };
		end else if ( cnt_ip_addr == 3'd6 && gmii_rxdv ) begin
			des_ip <= { des_ip[31:16], gmii_rxdata, des_ip[7:0] };
		end else if ( cnt_ip_addr == 3'd7 && gmii_rxdv ) begin
			des_ip <= { des_ip[31:8], gmii_rxdata };
		end else begin
			des_ip <= des_ip;
		end
	end else begin
		des_ip <= des_ip;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_udp_port <= 2'd0;
	end else if ( state == UDP_PORT ) begin
		if ( gmii_rxdv ) begin
			cnt_udp_port <= cnt_udp_port + 2'd1;
		end else begin
			cnt_udp_port <= cnt_udp_port;
		end
	end else begin
		cnt_udp_port <= 2'd0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		src_port <= 16'h0;
	end else if ( state == UDP_PORT ) begin
		if ( cnt_udp_port == 2'd0 && gmii_rxdv ) begin
			src_port <= { gmii_rxdata, src_port[7:0] };
		end else if ( cnt_udp_port == 2'd1 && gmii_rxdv ) begin
			src_port <= { src_port[15:8], gmii_rxdata } ;
		end else begin
			src_port <= src_port;
		end
	end else begin
		src_port <= src_port;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		des_port <= 16'h0;
	end else if ( state == UDP_PORT ) begin
		if ( cnt_udp_port == 2'd0 && gmii_rxdv ) begin
			des_port <= { gmii_rxdata, des_port[7:0] };
		end else if ( cnt_udp_port == 2'd1 && gmii_rxdv ) begin
			des_port <= { des_port[15:8], gmii_rxdata } ;
		end else begin
			des_port <= des_port;
		end
	end else begin
		des_port <= des_port;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_udp_len <= 1'b0;
	end else if ( state == UDP_LEN ) begin
		if ( gmii_rxdv ) begin
			cnt_udp_len <= ~cnt_udp_len;
		end else begin
			cnt_udp_len <= cnt_udp_len;
		end
	end else begin
		cnt_udp_len <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_len <= 16'd0;
	end else if ( state == UDP_LEN ) begin
		if ( !cnt_udp_len && gmii_rxdv ) begin
			udp_len <= { gmii_rxdata, udp_len[7:0] };
		end else if ( gmii_rxdv ) begin
			udp_len <= { udp_len[15:8], gmii_rxdata };
		end else begin
			udp_len <= udp_len;
		end
	end else begin
		udp_len <= udp_len;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_udp_check <= 1'b0;
	end else if ( state == UDP_CHECK ) begin
		if ( gmii_rxdv ) begin
			cnt_udp_check <= ~cnt_udp_check;
		end else begin
			cnt_udp_check <= cnt_udp_check;
		end
	end else begin
		cnt_udp_check <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		data_len <= 16'd0;
	end else begin
		data_len <= ip_len - ip_header_len;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_data <= 16'd0;
	end else if ( state == DATA || state == UDP_PORT || state == UDP_LEN || state == UDP_CHECK ) begin
		if ( gmii_rxdv ) begin
			cnt_data <= cnt_data + 16'd1;
		end else begin
			cnt_data <= cnt_data;
		end
	end else begin
		cnt_data <= 16'd0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_crc <= 2'd0;
	end else if ( state == CRC ) begin
		if ( gmii_rxdv ) begin
			cnt_crc <= cnt_crc + 2'd1;
		end else begin
			cnt_crc <= cnt_crc;
		end
	end else begin
		cnt_crc <= 2'd0;
	end
end

assign		pc_refresh		=	state == UDP_LEN && !cnt_udp_len && gmii_rxdv;

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		pc_mac_addr <= 48'h0;
		pc_ip_addr <= 32'h0;
		pc_port <= 16'h0;
		board_port <= 16'h0;
	end else if ( pc_refresh ) begin
		pc_mac_addr <= src_mac;
		pc_ip_addr <= src_ip;
		pc_port <= src_port;
		board_port <= des_port;
	end else begin
		pc_mac_addr <= pc_mac_addr;
		pc_ip_addr <= pc_ip_addr;
		pc_port <= pc_port;
		board_port <= board_port;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_rxdata <= 8'h0;
	end else if ( state == DATA ) begin
		udp_rxdata <= gmii_rxdata;
	end else begin
		udp_rxdata <= udp_rxdata;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_rxstart <= 1'b0;
	end else if ( !udp_continue && state == DATA && cnt_data == 16'd8 && gmii_rxdv ) begin
		udp_rxstart <= 1'b1;
	end else begin
		udp_rxstart <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_rxend <= 1'b0;
	end else if ( !flags[0] && state == DATA && cnt_data == data_len - 16'd1 && gmii_rxdv ) begin
		udp_rxend <= 1'b1;
	end else begin
		udp_rxend <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_rxdv <= 1'b0;
	end else if ( state == DATA && gmii_rxdv && udp_rxnum < udp_len - 8 ) begin
		udp_rxdv <= 1'b1;
	end else begin
		udp_rxdv <= 1'b0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_rxamount <= 16'd0;
	end else if ( state == UDP_CHECK ) begin
		udp_rxamount <= udp_len - 16'd8;
	end else begin
		udp_rxamount <= udp_rxamount;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_rxnum <= 16'd0;
	end else if ( udp_rxstart ) begin
		udp_rxnum <= 16'd1;
	end else if ( state == CRC && udp_rxnum >= udp_len - 8 ) begin
		udp_rxnum <= 16'd0;
	end else if ( state == DATA && gmii_rxdv && udp_rxnum < udp_len - 8 ) begin
		udp_rxnum <= udp_rxnum + 16'd1;
	end else begin
		udp_rxnum <= udp_rxnum;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_continue <= 1'b0;
	end else if ( state == CRC ) begin
		udp_continue <= flags[0];
	end else begin
		udp_continue <= udp_continue;
	end
end

endmodule