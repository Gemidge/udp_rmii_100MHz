// author:		Benjamin SMith
// create time:	2023/03/21 15:04
// edit time:	2023/03/22 16:21
// platform:	Cyclone ep4ce10f17i7, 野火 board
// module:		udp_gmii_tx
// function:	UDP transform data, only IPv4 supported. fragment is supported
// version:		1.0
// history:		0.1 don't support fragment

module udp_gmii_tx(
	input	wire							sys_clk,
	input	wire							sys_rst_n,
	input	wire							gmii_txbusy,
	output	wire							gmii_txen,
	output	reg		[7:0]					gmii_txdata,
	
	input	wire							udp_txstart,
	input	wire	[15:0]					udp_txamount,
	input	wire	[7:0]					udp_txdata,
	output	wire							udp_txreq,
	output	reg								udp_txbusy,
	
	input	wire	[47:0]					pc_mac_addr,
	input	wire	[31:0]					pc_ip_addr,
	input	wire	[15:0]					pc_port,
	input	wire	[15:0]					board_port
);

	parameter		BOARD_MAC_ADDR			= 48'h00_11_22_33_44_55;
	parameter		BOARD_IP_ADDR			= 32'hA9_FE_01_17;				// 169.254.1.23
	
	localparam		IDLE					= 18'h0_0001,
					PACKAGE_HEAD			= 18'h0_0002,
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
					UDP_PORT				= 18'h0_1000,					// source PORT and destination PORT
					UDP_LEN					= 18'h0_2000,					// udp length, ( = network length - IP header length ) if have not split
					UDP_CHECK				= 18'h0_4000,					// udp checksum, ignore it
					DATA					= 18'h0_8000,
					CRC						= 18'h1_0000,
					WAIT					= 18'h2_0000;

	reg		[17:0]							state;
	
	reg		[2:0]							cnt_package_head;
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
	reg		[15:0]							cnt_data;
	reg		[1:0]							cnt_crc;
	reg		[4:0]							cnt_wait;
	
	reg		[15:0]							ip_id;
	reg		[31:0]							ip_checksum;
	reg		[15:0]							data_len;						// data length of a transport package, subtract udp header, 18 ~ 1472
	reg		[15:0]							udp_len;						// data length of a udp package, (udp data + udp header), including all fragments, appears in udp protocol
	reg		[15:0]							ip_data_len;					// data length of a network package, appears in IPv4 protocol
	reg		[15:0]							flags;							// fragment flags and offset
	
	reg		[15:0]							udp_rest;						// data length of rest fragment data
	reg										udp_continue;

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		state <= IDLE;
	end else case ( state )
		IDLE: begin
			if ( ( udp_txstart && !udp_txbusy ) || udp_continue ) begin
				state <= PACKAGE_HEAD;
			end else begin
				state <= IDLE;
			end
		end
		PACKAGE_HEAD: begin
			if ( cnt_package_head >= 3'd7 && gmii_txen && !gmii_txbusy ) begin
				state <= MAC_ADDR;
			end else begin
				state <= PACKAGE_HEAD;
			end
		end
		MAC_ADDR: begin
			if ( cnt_mac_addr >= 4'd11 && gmii_txen && !gmii_txbusy ) begin
				state <= TYPE;
			end else begin
				state <= MAC_ADDR;
			end
		end
		TYPE: begin
			if ( cnt_type && gmii_txen && !gmii_txbusy ) begin
				state <= IP_TYPE;
			end else begin
				state <= TYPE;
			end
		end
		IP_TYPE: begin
			if ( cnt_ip_type && gmii_txen && !gmii_txbusy ) begin
				state <= IP_LEN;
			end else begin
				state <= IP_TYPE;
			end
		end
		IP_LEN: begin
			if ( cnt_ip_len && gmii_txen && !gmii_txbusy ) begin
				state <= IP_ID;
			end else begin
				state <= IP_LEN;
			end
		end
		IP_ID: begin
			if ( cnt_ip_id && gmii_txen && !gmii_txbusy ) begin
				state <= IP_SPLIT;
			end else begin
				state <= IP_ID;
			end
		end
		IP_SPLIT: begin
			if ( cnt_ip_split && gmii_txen && !gmii_txbusy ) begin
				state <= IP_TTL;
			end else begin
				state <= IP_SPLIT;
			end
		end
		IP_TTL: begin
			if ( gmii_txen && !gmii_txbusy ) begin
				state <= IP_PROTOCOL;
			end else begin
				state <= IP_TTL;
			end
		end
		IP_PROTOCOL: begin
			if ( gmii_txen && !gmii_txbusy ) begin
				state <= IP_CHECK;
			end else begin
				state <= IP_PROTOCOL;
			end
		end
		IP_CHECK: begin
			if ( cnt_ip_check && gmii_txen && !gmii_txbusy ) begin
				state <= IP_ADDR;
			end else begin
				state <= IP_CHECK;
			end
		end
		IP_ADDR: begin
			if ( cnt_ip_addr >= 3'd7 && udp_continue && gmii_txen && !gmii_txbusy ) begin
				state <= DATA;
			end else if ( cnt_ip_addr >= 3'd7 && gmii_txen && !gmii_txbusy ) begin
				state <= UDP_PORT;
			end else begin
				state <= IP_ADDR;
			end
		end
		UDP_PORT: begin
			if ( cnt_udp_port >= 2'd3 && gmii_txen && !gmii_txbusy ) begin
				state <= UDP_LEN;
			end else begin
				state <= UDP_PORT;
			end
		end
		UDP_LEN: begin
			if ( cnt_udp_len && gmii_txen && !gmii_txbusy ) begin
				state <= UDP_CHECK;
			end else begin
				state <= UDP_LEN;
			end
		end
		UDP_CHECK: begin
			if ( cnt_udp_check && gmii_txen && !gmii_txbusy ) begin
				state <= DATA;
			end else begin
				state <= UDP_CHECK;
			end
		end
		DATA: begin
			if ( cnt_data >= data_len - 1 && gmii_txen && !gmii_txbusy ) begin
				state <= CRC;
			end else begin
				state <= DATA;
			end
		end
		CRC: begin
			if ( cnt_crc >= 2'd3 && gmii_txen && !gmii_txbusy ) begin
				state <= WAIT;
			end else begin
				state <= CRC;
			end
		end
		WAIT: begin
			if ( cnt_wait >= 5'd31 ) begin
				state <= IDLE;
			end else begin
				state <= WAIT;
			end
		end
		default: state <= IDLE;
	endcase
end

assign		gmii_txen		=	( state != IDLE && state != WAIT );
assign		udp_txreq		=	( ( state ==IP_ADDR && cnt_ip_addr >= 3'd7 && udp_continue ) || ( state == UDP_CHECK && cnt_udp_check ) || ( state == DATA && cnt_data < udp_rest - 1 && cnt_data < 'd1479 ) ) && gmii_txen && !gmii_txbusy;

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_txbusy <= 1'b0;
	end else if ( udp_txstart ) begin
		udp_txbusy <= 1'b1;
	end else if ( state == IDLE && !udp_continue ) begin
		udp_txbusy <= 1'b0;
	end else begin
		udp_txbusy <= udp_txbusy;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_package_head <= 3'd0;
	end else if ( state == PACKAGE_HEAD ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
			cnt_package_head <= cnt_package_head + 3'd1;
		end else begin
			cnt_package_head <= cnt_package_head;
		end
	end else begin
		cnt_package_head <= 3'd0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_mac_addr <= 4'd0;
	end else if ( state == MAC_ADDR ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		cnt_type <= 1'b0;
	end else if ( state == TYPE ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		cnt_ip_type <= 1'b0;
	end else if ( state == IP_TYPE ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		cnt_ip_len <= 1'b0;
	end else if ( state == IP_LEN ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		cnt_ip_id <= 1'b0;
	end else if ( state == IP_ID ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		cnt_ip_split <= 1'b0;
	end else if ( state == IP_SPLIT ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		cnt_ip_check <= 1'b0;
	end else if ( state == IP_CHECK ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		if ( gmii_txen && !gmii_txbusy ) begin
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
		cnt_udp_port <= 2'd0;
	end else if ( state == UDP_PORT ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		cnt_udp_len <= 1'b0;
	end else if ( state == UDP_LEN ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		cnt_udp_check <= 1'b0;
	end else if ( state == UDP_CHECK ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		ip_id <= 16'd0;
	end else if ( udp_txstart && !udp_txbusy ) begin
		ip_id <= ip_id + 16'd1;
	end else begin
		ip_id <= ip_id;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		ip_checksum <= 32'h0;
	end else if ( state == IP_SPLIT && cnt_ip_split && gmii_txen && !gmii_txbusy ) begin
		ip_checksum <= 16'h4500 + ip_data_len + ip_id + 16'h0000 + 16'h4011 + BOARD_IP_ADDR[31:16] + BOARD_IP_ADDR[15:0] + pc_ip_addr[31:16] + pc_ip_addr[15:0];
	end else if ( state == IP_TTL ) begin
		ip_checksum <= ip_checksum[31:16] + ip_checksum[15:0];
	end else begin
		ip_checksum <= ip_checksum;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		data_len <= 16'd26;
	end else if ( udp_rest >= 'd26 && udp_rest <= 'd1480 ) begin
		data_len <= udp_rest;
	end else if ( udp_rest < 'd26 ) begin
		data_len <= 16'd26;
	end else begin
		data_len <= 16'd1480;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		ip_data_len <= 16'd46;
	end else if ( udp_rest <= 'd1480 ) begin
		ip_data_len <= udp_rest + 16'd20;
	end else begin
		ip_data_len <= 16'd1500;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_len <= 16'd0;
	end else if ( udp_txstart && !udp_txbusy ) begin
		udp_len <= udp_txamount + 16'd8;
	end else begin
		udp_len <= udp_len;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_continue <= 1'b0;
	end else if ( state == DATA && udp_rest > 'd1480 ) begin
		udp_continue <= 1'b1;
	end else if ( state == DATA ) begin
		udp_continue <= 1'b0;
	end else begin
		udp_continue <= udp_continue;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		udp_rest <= 16'd0;
	end else if ( udp_txstart && !udp_txbusy ) begin
		udp_rest <= udp_txamount + 16'd8;
	end else if ( state == CRC && cnt_crc == 0 && gmii_txen && !gmii_txbusy ) begin
		if ( udp_rest > 'd1480 ) begin
			udp_rest <= udp_rest - 16'd1480;
		end else begin
			udp_rest <= udp_rest;
		end
	end	else begin
		udp_rest <= udp_rest;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		flags[15:13] <= 3'h0;
	end else if ( state == TYPE && cnt_type && gmii_txen && !gmii_txbusy ) begin
		if ( udp_rest > 'd1480 ) begin
			flags[15:13] <= 3'h1;
		end else begin
			flags[15:13] <= 3'h0;
		end
	end else begin
		flags[15:13] <= flags[15:13];
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		flags[12:0] <= 13'd0;
	end else if ( state == TYPE && cnt_type && gmii_txen && !gmii_txbusy ) begin
		if ( udp_continue ) begin
			flags[12:0] <= flags[12:0] + 13'd185;
		end else begin
			flags[12:0] <= 13'd0;
		end
	end else begin
		flags[12:0] <= flags[12:0];
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_data <= 16'd0;
	end else if ( state == UDP_PORT || state == UDP_LEN || state == UDP_CHECK || state == DATA ) begin
		if ( gmii_txen && !gmii_txbusy ) begin
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
		if ( gmii_txen && !gmii_txbusy ) begin
			cnt_crc <= cnt_crc + 2'd1;
		end else begin
			cnt_crc <= cnt_crc;
		end
	end else begin
		cnt_crc <= 2'd0;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		cnt_wait <= 5'd0;
	end else if ( state == WAIT ) begin
		cnt_wait <= cnt_wait + 5'd1;
	end else begin
		cnt_wait <= 5'd0;
	end
end

	wire									crc_start;
	wire									crc_end;
	wire									crc_en;
	wire	[31:0]							crc32_temp;
	wire									crc32_valid;
	reg		[31:0]							crc32;
	
assign		crc_start	=	( state == MAC_ADDR ) && ( cnt_mac_addr == 4'd0 ) && gmii_txen && !gmii_txbusy;
assign		crc_end		=	( state == DATA ) && ( cnt_data == data_len - 1 ) && gmii_txen && !gmii_txbusy;
assign		crc_en		=	( state != IDLE ) && ( state != PACKAGE_HEAD ) && ( state != CRC ) && gmii_txen && !gmii_txbusy;

CRC32_D8									u1_CRC32_D8 (
	.sys_clk								( sys_clk		),
	.sys_rst_n								( sys_rst_n		),
	.data									( gmii_txdata	),
	.crc_start								( crc_start		),
	.crc_en									( crc_en		),
	.crc_end								( crc_end		),
	.crc32									( crc32_temp	),
	.crc32_valid							( crc32_valid	)
);

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		crc32 <= 32'h0;
	end else if ( crc32_valid ) begin
		crc32 <= crc32_temp;
	end else begin
		crc32 <= crc32;
	end
end

always @ ( posedge sys_clk or negedge sys_rst_n ) begin
	if ( !sys_rst_n ) begin
		gmii_txdata <= 8'h0;
	end else case ( state )
		IDLE: begin
			if ( udp_txstart || udp_continue ) begin
				gmii_txdata <= 8'h55;
			end else begin
				gmii_txdata <= 8'h0;
			end
		end
		PACKAGE_HEAD: begin
			if ( cnt_package_head == 3'd6 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'hD5;
			end else if ( cnt_package_head == 3'd7 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_mac_addr[47:40];
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		MAC_ADDR: begin
			if ( cnt_mac_addr == 4'd0 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_mac_addr[39:32];
			end else if ( cnt_mac_addr == 4'd1 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_mac_addr[31:24];
			end else if ( cnt_mac_addr == 4'd2 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_mac_addr[23:16];
			end else if ( cnt_mac_addr == 4'd3 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_mac_addr[15:8];
			end else if ( cnt_mac_addr == 4'd4 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_mac_addr[7:0];
			end else if ( cnt_mac_addr == 4'd5 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_MAC_ADDR[47:40];
			end else if ( cnt_mac_addr == 4'd6 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_MAC_ADDR[39:32];
			end else if ( cnt_mac_addr == 4'd7 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_MAC_ADDR[31:24];
			end else if ( cnt_mac_addr == 4'd8 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_MAC_ADDR[23:16];
			end else if ( cnt_mac_addr == 4'd9 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_MAC_ADDR[15:8];
			end else if ( cnt_mac_addr == 4'd10 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_MAC_ADDR[7:0];
			end else if ( cnt_mac_addr == 4'd11 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'h08;
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		TYPE: begin
			if ( !cnt_type && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'h00;
			end else if ( cnt_type && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'h45;
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		IP_TYPE: begin
			if ( !cnt_ip_type && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'h00;
			end else if ( cnt_ip_type && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= ip_data_len[15:8];
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		IP_LEN: begin
			if ( !cnt_ip_len && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= ip_data_len[7:0];
			end else if ( cnt_ip_len && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= ip_id[15:8];
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		IP_ID: begin
			if ( !cnt_ip_id && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= ip_id[7:0];
			end else if ( cnt_ip_id && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= flags[15:8];
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		IP_SPLIT: begin
			if ( !cnt_ip_split && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= flags[7:0];
			end else if ( cnt_ip_split && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'h40;
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		IP_TTL: begin
			if ( gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'd17;
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		IP_PROTOCOL: begin
			if ( gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= ip_checksum[15:8] ^ 8'hff;
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		IP_CHECK: begin
			if ( !cnt_ip_check && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= ip_checksum[7:0] ^ 8'hff;
			end else if ( cnt_ip_check && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_IP_ADDR[31:24];
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		IP_ADDR: begin
			if ( cnt_ip_addr == 3'd0 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_IP_ADDR[23:16];
			end else if ( cnt_ip_addr == 3'd1 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_IP_ADDR[15:8];
			end else if ( cnt_ip_addr == 3'd2 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= BOARD_IP_ADDR[7:0];
			end else if ( cnt_ip_addr == 3'd3 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_ip_addr[31:24];
			end else if ( cnt_ip_addr == 3'd4 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_ip_addr[23:16];
			end else if ( cnt_ip_addr == 3'd5 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_ip_addr[15:8];
			end else if ( cnt_ip_addr == 3'd6 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_ip_addr[7:0];
			end else if ( cnt_ip_addr == 3'd7 && gmii_txen && !gmii_txbusy && udp_continue ) begin
				gmii_txdata <= udp_txdata;
			end else if ( cnt_ip_addr == 3'd7 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= board_port[15:8];
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		UDP_PORT: begin
			if ( cnt_udp_port == 2'd0 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= board_port[7:0];
			end else if ( cnt_udp_port == 2'd1 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_port[15:8];
			end else if ( cnt_udp_port == 2'd2 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= pc_port[7:0];
			end else if ( cnt_udp_port == 2'd3 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= udp_len[15:8];
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		UDP_LEN: begin
			if ( !cnt_udp_len && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= udp_len[7:0];
			end else if ( cnt_udp_len && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'h0;
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		UDP_CHECK: begin
			if ( !cnt_udp_check && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'h0;
			end else if ( cnt_udp_check && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= udp_txdata;
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		DATA: begin
			if ( cnt_data >= data_len - 1 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= crc32_temp[7:0];
			end else if ( gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= udp_txdata;
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		CRC: begin
			if ( cnt_crc == 2'd0 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= crc32[15:8];
			end else if ( cnt_crc == 2'd1 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= crc32[23:16];
			end else if ( cnt_crc == 2'd2 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= crc32[31:24];
			end else if ( cnt_crc == 2'd3 && gmii_txen && !gmii_txbusy ) begin
				gmii_txdata <= 8'h0;
			end else begin
				gmii_txdata <= gmii_txdata;
			end
		end
		default: gmii_txdata <= 8'h0;
	endcase
end

endmodule