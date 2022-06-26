library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_textio.all;
use ieee.std_logic_unsigned.all;
use std.textio.all;
use ieee.numeric_std.all;

entity tb is
	generic(
		address_width: integer := 15;
		memory_file : string := "code.txt";
		log_file: string := "out.txt";
		uart_support : string := "no"
	);
end tb;

architecture tb of tb is


	signal clock_in, reset, data, stall, stall_sig: std_logic := '0';
	signal uart_read, uart_write: std_logic;
	signal boot_enable_n, ram_enable_n, ram_dly: std_logic;
	signal address, data_read, data_write, data_read_boot, data_read_ram: std_logic_vector(31 downto 0);
	signal ext_irq: std_logic_vector(7 downto 0);
	signal data_we, data_w_n_ram: std_logic_vector(3 downto 0);

	signal periph, periph_dly, periph_wr, periph_irq: std_logic;
	signal data_read_periph, data_read_periph_s, data_write_periph: std_logic_vector(31 downto 0);
	signal gpioa_in, gpioa_out, gpioa_ddr: std_logic_vector(15 downto 0);
	signal gpiob_in, gpiob_out, gpiob_ddr: std_logic_vector(15 downto 0);
	signal gpio_sig, gpio_sig2, gpio_sig3: std_logic := '0';
	
	signal ext_periph, ext_periph_dly, ready: std_logic;
	signal key: std_logic_vector(127 downto 0);
	signal input, output: std_logic_vector(63 downto 0);
	signal data_read_xtea, data_read_xtea_s: std_logic_vector(31 downto 0);
	signal control: std_logic_vector(1 downto 0);

	signal data_read_wrapper	: std_logic_vector(31 downto 0);
	signal data_read_wrapper_s	: std_logic_vector(31 downto 0);
	
	signal wrapper_buffer_0		: std_logic_vector(31 downto 0);
	signal wrapper_buffer_1		: std_logic_vector(31 downto 0);
	signal wrapper_buffer_2		: std_logic_vector(31 downto 0);
	signal wrapper_buffer_3		: std_logic_vector(31 downto 0);

	signal wrapper_buffer_4		: std_logic_vector(31 downto 0);
	signal wrapper_buffer_5		: std_logic_vector(31 downto 0);
	signal wrapper_buffer_6		: std_logic_vector(31 downto 0);
	signal wrapper_buffer_7		: std_logic_vector(31 downto 0);


	signal out_aes_0		: std_logic_vector(31 downto 0);
	signal out_aes_1		: std_logic_vector(31 downto 0);
	signal out_aes_2		: std_logic_vector(31 downto 0);
	signal out_aes_3		: std_logic_vector(31 downto 0);
	signal control_aes		: std_logic_vector(31 downto 0) := (others => '0');


	signal ext_wrapper, ext_wrapper_reg : std_logic;
	signal enable_data_wrapper : std_logic;

	-- MINI AES

	signal load_miniaes		: std_logic;
	signal enc_miniaes		: std_logic;
	signal done_miniaes		: std_logic;

	signal key_miniaes		: std_logic_vector(7 downto 0);
	signal data_out_miniaes	: std_logic_vector(7 downto 0);
	signal data_in_miniaes	: std_logic_vector(7 downto 0);	

	signal enable_aes 	: std_logic;
	signal enc_aes		: std_logic;
	
	signal out_miniaes : std_logic_vector(127 downto 0);

	type state is (wb0p0, wb0p8, wb0p16, wb0p24, wb1p0, wb1p8, wb1p16, wb1p24, wb2p0, wb2p8, wb2p16, wb2p24, wb3p0, wb3p8, wb3p16, wb3p24, finish);
	signal fsm : state;

	signal finish_load_aes : std_logic := '0';
	signal rst_aes, rst_aes_r : std_logic := '1';
	signal start_aes : std_logic := '0';

	signal out_aes_it : std_logic_vector(3 downto 0) := (others => '0');
	


begin

	process						--25Mhz system clock
	begin
		clock_in <= not clock_in;
		wait for 20 ns;
		clock_in <= not clock_in;
		wait for 20 ns;
	end process;

	process
	begin
		wait for 4 ms;
		gpio_sig <= not gpio_sig;
		gpio_sig2 <= not gpio_sig2;
		wait for 100 us;
		gpio_sig <= not gpio_sig;
		gpio_sig2 <= not gpio_sig2;
	end process;

	process
	begin
		wait for 5 ms;
		gpio_sig3 <= not gpio_sig3;
		wait for 5 ms;
		gpio_sig3 <= not gpio_sig3;
	end process;

	gpioa_in <= x"00" & "0000" & gpio_sig & "000";
	gpiob_in <= "10000" & gpio_sig3 & "00" & "00000" & gpio_sig2 & "00";

	process
	begin
		stall <= not stall;
		wait for 123 ns;
		stall <= not stall;
		wait for 123 ns;
	end process;

	reset <= '0', '1' after 5 ns, '0' after 500 ns;
	stall_sig <= '0'; --stall;
	ext_irq <= "0000000" & periph_irq;

	boot_enable_n <= '0' when (address(31 downto 28) = "0000" and stall_sig = '0') or reset = '1' else '1';
	ram_enable_n <= '0' when (address(31 downto 28) = "0100" and stall_sig = '0') or reset = '1' else '1';
	-- else data_read_xtea when ext_periph = '1'
	data_read <= data_read_wrapper when ext_wrapper_reg = '1' or ext_periph_dly = '1' else data_read_periph when periph = '1' or periph_dly = '1' else data_read_boot when address(31 downto 28) = "0000" and ram_dly = '0' else data_read_ram;
	data_w_n_ram <= not data_we;

	process(clock_in, reset)
	begin
		if reset = '1' then
			ram_dly <= '0';
			periph_dly <= '0';
			ext_periph_dly <= '0';
		elsif clock_in'event and clock_in = '1' then
			ram_dly <= not ram_enable_n;
			periph_dly <= periph;
			ext_periph_dly <= ext_periph;
		end if;
	end process;

	-- HF-RISCV core
	processor: entity work.processor
	port map(	clk_i => clock_in,
			rst_i => reset,
			stall_i => stall_sig,
			addr_o => address,
			data_i => data_read,
			data_o => data_write,
			data_w_o => data_we,
			data_mode_o => open,
			extio_in => ext_irq,
			extio_out => open
	);


	data_read_wrapper <= data_read_wrapper_s(7 downto 0) & data_read_wrapper_s(15 downto 8) & data_read_wrapper_s(23 downto 16) & data_read_wrapper_s(31 downto 24);
	
	ext_wrapper <= '1' when address(31 downto 24) = x"e6" else '0';

	process(clock_in, reset)
	begin
		if reset = '1' then
			ext_wrapper_reg <= '0';
		elsif clock_in'event and clock_in = '1' then
			ext_wrapper_reg <= ext_wrapper;
		end if;
	end process;


	-- data_read_wrapper_s <= wrapper_buffer_0 when(address(7 downto 4) = "0101") else
	-- 					 wrapper_buffer_1 when(address(7 downto 4) = "0110") else
	-- 					 wrapper_buffer_2 when(address(7 downto 4) = "0111") else
	-- 					 wrapper_buffer_3 when(address(7 downto 4) = "1000") else
	-- 					 (others => '0');

	-- data_read_wrapper_s <= 	out_aes_0 when(address(7 downto 4) = x"9") else
	-- 						out_aes_1 when(address(7 downto 4) = x"A") else
	-- 					 	out_aes_2 when(address(7 downto 4) = x"B") else
	-- 					 	out_aes_3 when(address(7 downto 4) = x"C") else
	-- 						control_aes when(address(7 downto 4) = x"D");

	process(clock_in)
	begin
			if clock_in'event and clock_in = '1' then
				case address(7 downto 4) is
					when x"9" =>
						data_read_wrapper_s <= out_aes_0;
					when x"A" =>
						data_read_wrapper_s <= out_aes_1;
					when x"B" =>
						data_read_wrapper_s <= out_aes_2;
					when x"C" =>
						data_read_wrapper_s <= out_aes_3;
					when x"D" => 
						data_read_wrapper_s <= control_aes;
					when others =>
				end case;
			end if;
	end process;


							--  else data_read_wrapper_s;

	
	
	process (clock_in, reset)
	begin
		if reset = '1' then
	 		wrapper_buffer_0 <= (others => '0');
			wrapper_buffer_1 <= (others => '0');
			wrapper_buffer_2 <= (others => '0');
			wrapper_buffer_3 <= (others => '0');
			wrapper_buffer_4 <= (others => '0');
			wrapper_buffer_5 <= (others => '0');
			wrapper_buffer_6 <= (others => '0');
			wrapper_buffer_7 <= (others => '0');

	 	elsif clock_in'event and clock_in = '1' then
	 		if (ext_wrapper = '1') then	-- Wrapper is at 0xe6000000
	 			case address(7 downto 4) is
					when x"0" => 
						enable_aes <= data_write(24);
						enc_aes <= data_write(25);
					when x"1" =>
						wrapper_buffer_0 <=  data_write(7 downto 0) & data_write(15 downto 8) & data_write(23 downto 16) & data_write(31 downto 24);
					when x"2" =>
						wrapper_buffer_1 <= data_write(7 downto 0) & data_write(15 downto 8) & data_write(23 downto 16) & data_write(31 downto 24);
					when x"3" =>
						wrapper_buffer_2 <= data_write(7 downto 0) & data_write(15 downto 8) & data_write(23 downto 16) & data_write(31 downto 24);
					when x"4" =>
						wrapper_buffer_3 <= data_write(7 downto 0) & data_write(15 downto 8) & data_write(23 downto 16) & data_write(31 downto 24);
					when x"5" =>
						wrapper_buffer_4 <=  data_write(7 downto 0) & data_write(15 downto 8) & data_write(23 downto 16) & data_write(31 downto 24);
					when x"6" =>
						wrapper_buffer_5 <= data_write(7 downto 0) & data_write(15 downto 8) & data_write(23 downto 16) & data_write(31 downto 24);
					when x"7" =>
						wrapper_buffer_6 <= data_write(7 downto 0) & data_write(15 downto 8) & data_write(23 downto 16) & data_write(31 downto 24);
					when x"8" =>
						wrapper_buffer_7 <= data_write(7 downto 0) & data_write(15 downto 8) & data_write(23 downto 16) & data_write(31 downto 24);
					when others =>
	 			end case;
	 		end if;
	 	end if;
	end process;

	load_bytes_to_aes: process (clock_in, reset, enable_aes)
	begin
		if enable_aes'event and enable_aes = '1' then
			finish_load_aes <= '0';
		end if;

		if clock_in'event and clock_in = '1' then
			if enable_aes = '1' and finish_load_aes = '0' then
			-- if enable_aes = '1' then
				case fsm is
					when wb0p0 =>
						key_miniaes <= wrapper_buffer_0(7 downto 0);
						data_in_miniaes <= wrapper_buffer_4(7 downto 0);
						load_miniaes <= '1';
					when wb0p8 =>
						key_miniaes <= wrapper_buffer_0(15 downto 8);
						data_in_miniaes <= wrapper_buffer_4(15 downto 8);
					when wb0p16 =>
						key_miniaes <= wrapper_buffer_0(23 downto 16);
						data_in_miniaes <= wrapper_buffer_4(23 downto 16);
					when wb0p24 =>
						key_miniaes <= wrapper_buffer_0(31 downto 24);
						data_in_miniaes <= wrapper_buffer_4(31 downto 24);
					when wb1p0 =>
						key_miniaes <= wrapper_buffer_1(7 downto 0);
						data_in_miniaes <= wrapper_buffer_5(7 downto 0);
					when wb1p8 =>
						key_miniaes <= wrapper_buffer_1(15 downto 8);
						data_in_miniaes <= wrapper_buffer_5(15 downto 8);
					when wb1p16 =>
						key_miniaes <= wrapper_buffer_1(23 downto 16);
						data_in_miniaes <= wrapper_buffer_5(23 downto 16);
					when wb1p24 =>
						key_miniaes <= wrapper_buffer_1(31 downto 24);
						data_in_miniaes <= wrapper_buffer_5(31 downto 24);
					when wb2p0 =>
						key_miniaes <= wrapper_buffer_2(7 downto 0);
						data_in_miniaes <= wrapper_buffer_6(7 downto 0);
					when wb2p8 =>
						key_miniaes <= wrapper_buffer_2(15 downto 8);
						data_in_miniaes <= wrapper_buffer_6(15 downto 8);
					when wb2p16 =>
						key_miniaes <= wrapper_buffer_2(23 downto 16);
						data_in_miniaes <= wrapper_buffer_6(23 downto 16);
					when wb2p24 =>
						key_miniaes <= wrapper_buffer_2(31 downto 24);
						data_in_miniaes <= wrapper_buffer_6(31 downto 24);
					when wb3p0 =>
						key_miniaes <= wrapper_buffer_3(7 downto 0);
						data_in_miniaes <= wrapper_buffer_7(7 downto 0);
					when wb3p8 =>
						key_miniaes <= wrapper_buffer_3(15 downto 8);
						data_in_miniaes <= wrapper_buffer_7(15 downto 8);
					when wb3p16 =>
						key_miniaes <= wrapper_buffer_3(23 downto 16);
						data_in_miniaes <= wrapper_buffer_7(23 downto 16);
					when wb3p24 =>
						key_miniaes <= wrapper_buffer_3(31 downto 24);
						data_in_miniaes <= wrapper_buffer_7(31 downto 24);
					when finish =>
						finish_load_aes <= '1';
						enc_miniaes <= enc_aes;
						load_miniaes <= '0';
					when others =>
				end case;			
			end if;
		end if;
	end process;


	inc_fsm: process (clock_in, reset)
	begin
		if clock_in'event and clock_in = '1' then
			if enable_aes = '1' and finish_load_aes = '0' then
				case fsm is
					when wb0p0 =>
						fsm <= wb0p8;
					when wb0p8 =>
						fsm <= wb0p16;
					when wb0p16 =>
						fsm <= wb0p24;
					when wb0p24 =>
						fsm <= wb1p0;
					when wb1p0 =>
						fsm <= wb1p8;
					when wb1p8 =>
						fsm <= wb1p16;
					when wb1p16 =>
						fsm <= wb1p24;
					when wb1p24 =>
						fsm <= wb2p0;
					when wb2p0 =>
						fsm <= wb2p8;
					when wb2p8 =>
						fsm <= wb2p16;
					when wb2p16 =>
						fsm <= wb2p24;
					when wb2p24 =>
						fsm <= wb3p0;
					when wb3p0 =>
						fsm <= wb3p8;
					when wb3p8 =>
						fsm <= wb3p16;
					when wb3p16 =>
						fsm <= wb3p24;
					when wb3p24 =>
						fsm <= finish;
					when finish =>
						fsm <= wb0p0;
					when others =>
				end case;
			end if;
		end if;
	end process;

	rcv_data_aes: process(clock_in)
	begin
		if clock_in'event and clock_in = '1' then
			if done_miniaes = '1' then
				out_aes_it <= out_aes_it + 1;
				case out_aes_it is
					when x"0" =>
						out_aes_0(7 downto 0) <= data_out_miniaes;
					when x"1" =>
						out_aes_0(15 downto 8) <= data_out_miniaes;
					when x"2" =>
						out_aes_0(23 downto 16) <= data_out_miniaes;
					when x"3" =>
						out_aes_0(31 downto 24) <= data_out_miniaes;
					when x"4" =>
						out_aes_1(7 downto 0) <= data_out_miniaes;
					when x"5" =>
						out_aes_1(15 downto 8) <= data_out_miniaes;
					when x"6" =>
						out_aes_1(23 downto 16) <= data_out_miniaes;
					when x"7" =>
						out_aes_1(31 downto 24) <= data_out_miniaes;
					when x"8" =>
						out_aes_2(7 downto 0) <= data_out_miniaes;
					when x"9" =>
						out_aes_2(15 downto 8) <= data_out_miniaes;
					when x"A" =>
						out_aes_2(23 downto 16) <= data_out_miniaes;
					when x"B" =>
						out_aes_2(31 downto 24) <= data_out_miniaes;
					when x"C" =>
						out_aes_3(7 downto 0) <= data_out_miniaes;
					when x"D" =>
						out_aes_3(15 downto 8) <= data_out_miniaes;
					when x"E" =>
						out_aes_3(23 downto 16) <= data_out_miniaes;
					when x"F" =>
						out_aes_3(31 downto 24) <= data_out_miniaes;
						-- rst_aes <= '1';
					when others =>
				end case;
			end if;
		end if;
	end process;



	-- clear_aes: process(done_miniaes, rst_aes_r)
	-- 	begin
	-- 	-- if clock_in'event and clock_in = '1' then
	-- 		if reset = 	'0' then
	-- 			if done_miniaes'event and done_miniaes = '0' and rst_aes_r = '0' then
	-- 				rst_aes <= '1';
	-- 			else
	-- 				rst_aes <= '0';
	-- 			end if;
	-- 		end if;
	-- 	-- end if;
	-- end process clear_aes;

	-- done_flop: process(clock_in, reset)
	-- begin
	-- 	if reset = '1'then
	-- 		rst_aes_r <= '0';
	-- 	elsif clock_in'event and clock_in = '1' then
	-- 		rst_aes_r <= rst_aes;
	-- 	end if;
	-- end process done_flop;

	process(done_miniaes, load_miniaes)
	begin
		if load_miniaes'event and load_miniaes = '1' then
			rst_aes <= '0';
			control_aes <= (others => '0');
		elsif done_miniaes'event and done_miniaes = '0' then
			rst_aes <= '1';
			control_aes <= (others => '1');
		end if;
	end process;


	miniaes: entity work.mini_aes
	port map(
		clock => clock_in,
		clear => rst_aes,
		load_i => load_miniaes,
		enc => enc_miniaes,
		key_i => key_miniaes,
		data_i => data_in_miniaes,
		data_o => data_out_miniaes,
		done_o => done_miniaes
	);

	data_read_periph <= data_read(7 downto 0) & data_read(15 downto 8) & data_read(23 downto 16) & data_read(31 downto 24);
	data_write_periph <= data_write(7 downto 0) & data_write(15 downto 8) & data_write(23 downto 16) & data_write(31 downto 24);
	
	periph_wr <= '1' when data_we /= "0000" else '0';
	periph <= '1' when address(31 downto 24) = x"e1" else '0';

	peripherals: entity work.peripherals
	port map(
		clk_i => clock_in,
		rst_i => reset,
		addr_i => address,
		data_i => data_write_periph,
		data_o => data_read_periph_s,
		sel_i => periph,
		wr_i => periph_wr,
		irq_o => periph_irq,
		gpioa_in => gpioa_in,
		gpioa_out => gpioa_out,
		gpioa_ddr => gpioa_ddr,
		gpiob_in => gpiob_in,
		gpiob_out => gpiob_out,
		gpiob_ddr => gpiob_ddr
	);

	-- boot ROM
	boot0lb: entity work.boot_ram
	generic map (	memory_file => "boot.txt",
					data_width => 8,
					address_width => 12,
					bank => 0)
	port map(
		clk 	=> clock_in,
		addr 	=> address(11 downto 2),
		cs_n 	=> boot_enable_n,
		we_n	=> '1',
		data_i	=> (others => '0'),
		data_o	=> data_read_boot(7 downto 0)
	);

	boot0ub: entity work.boot_ram
	generic map (	memory_file => "boot.txt",
					data_width => 8,
					address_width => 12,
					bank => 1)
	port map(
		clk 	=> clock_in,
		addr 	=> address(11 downto 2),
		cs_n 	=> boot_enable_n,
		we_n	=> '1',
		data_i	=> (others => '0'),
		data_o	=> data_read_boot(15 downto 8)
	);

	boot1lb: entity work.boot_ram
	generic map (	memory_file => "boot.txt",
					data_width => 8,
					address_width => 12,
					bank => 2)
	port map(
		clk 	=> clock_in,
		addr 	=> address(11 downto 2),
		cs_n 	=> boot_enable_n,
		we_n	=> '1',
		data_i	=> (others => '0'),
		data_o	=> data_read_boot(23 downto 16)
	);

	boot1ub: entity work.boot_ram
	generic map (	memory_file => "boot.txt",
					data_width => 8,
					address_width => 12,
					bank => 3)
	port map(
		clk 	=> clock_in,
		addr 	=> address(11 downto 2),
		cs_n 	=> boot_enable_n,
		we_n	=> '1',
		data_i	=> (others => '0'),
		data_o	=> data_read_boot(31 downto 24)
	);

	-- RAM
	memory0lb: entity work.bram
	generic map (	memory_file => memory_file,
					data_width => 8,
					address_width => address_width,
					bank => 0)
	port map(
		clk 	=> clock_in,
		addr 	=> address(address_width -1 downto 2),
		cs_n 	=> ram_enable_n,
		we_n	=> data_w_n_ram(0),
		data_i	=> data_write(7 downto 0),
		data_o	=> data_read_ram(7 downto 0)
	);

	memory0ub: entity work.bram
	generic map (	memory_file => memory_file,
					data_width => 8,
					address_width => address_width,
					bank => 1)
	port map(
		clk 	=> clock_in,
		addr 	=> address(address_width -1 downto 2),
		cs_n 	=> ram_enable_n,
		we_n	=> data_w_n_ram(1),
		data_i	=> data_write(15 downto 8),
		data_o	=> data_read_ram(15 downto 8)
	);

	memory1lb: entity work.bram
	generic map (	memory_file => memory_file,
					data_width => 8,
					address_width => address_width,
					bank => 2)
	port map(
		clk 	=> clock_in,
		addr 	=> address(address_width -1 downto 2),
		cs_n 	=> ram_enable_n,
		we_n	=> data_w_n_ram(2),
		data_i	=> data_write(23 downto 16),
		data_o	=> data_read_ram(23 downto 16)
	);

	memory1ub: entity work.bram
	generic map (	memory_file => memory_file,
					data_width => 8,
					address_width => address_width,
					bank => 3)
	port map(
		clk 	=> clock_in,
		addr 	=> address(address_width -1 downto 2),
		cs_n 	=> ram_enable_n,
		we_n	=> data_w_n_ram(3),
		data_i	=> data_write(31 downto 24),
		data_o	=> data_read_ram(31 downto 24)
	);

	-- debug process
	debug:
	-- if uart_support = "no" generate
		process(clock_in, address)
			file store_file : text open write_mode is "debug.txt";
			variable hex_file_line : line;
			variable c : character;
			variable index : natural;
			variable line_length : natural := 0;
		begin
			if clock_in'event and clock_in = '1' then
				if address = x"f00000d0" and data = '0' then
					data <= '1';
					index := conv_integer(data_write(30 downto 24));
					if index /= 10 then
						c := character'val(index);
						write(hex_file_line, c);
						line_length := line_length + 1;
					end if;
					if index = 10 or line_length >= 72 then
						writeline(store_file, hex_file_line);
						line_length := 0;
					end if;
				else
					data <= '0';
				end if;
			end if;
		end process;
	-- end generate;

	process(clock_in, reset, address)
	begin
		if reset = '1' then
		elsif clock_in'event and clock_in = '0' then
			assert address /= x"e0000000" report "end of simulation" severity failure;
			assert (address < x"50000000") or (address >= x"e0000000") report "out of memory region" severity failure;
			assert address /= x"40000104" report "handling IRQ" severity warning;
		end if;
	end process;

end tb;

