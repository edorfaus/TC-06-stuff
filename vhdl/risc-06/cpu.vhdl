library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu is
	port(
		o_ram_write: out std_logic;
		o_ram_address: out std_logic_vector(7 downto 0);
		o_ram_data: out std_logic_vector(7 downto 0);
		i_ram_data: in std_logic_vector(7 downto 0);

		o_dev_active: out std_logic;
		o_dev_write: out std_logic;
		o_dev_address: out std_logic_vector(1 downto 0);
		o_dev_data: out std_logic_vector(7 downto 0);
		i_dev_data: in std_logic_vector(7 downto 0);

		i_reset: in std_logic;
		i_clock: in std_logic;
		i_enable: in std_logic;
		o_halted: out std_logic
	);
end cpu;

architecture cpu_arch of cpu is
	component comparator is
		port(
			i_operator: in std_logic_vector(1 downto 0);
			i_value_0: in std_logic_vector(7 downto 0);
			i_value_1: in std_logic_vector(7 downto 0);
			o_result: out std_logic
		);
	end component comparator;

	type state_type is (
		HALT, FETCH, DECODE, RUN, DAT_DONE
	);
	type registers_type is array (1 downto 0) of std_logic_vector(7 downto 0);

	signal r_ram_write: std_logic;
	signal r_ram_address: std_logic_vector(7 downto 0);
	signal r_ram_data_out: std_logic_vector(7 downto 0);

	signal r_dev_active: std_logic;
	signal r_dev_write: std_logic;
	signal r_dev_address: std_logic_vector(1 downto 0);
	signal r_dev_data_out: std_logic_vector(7 downto 0);

	signal r_registers: registers_type;
	signal r_program_counter: std_logic_vector(7 downto 0);
	signal r_instruction: std_logic_vector(7 downto 0);
	signal r_state: state_type;

	signal r_mov_offset: std_logic_vector(7 downto 0);

	signal w_pc_plus_1: std_logic_vector(7 downto 0);
	signal w_brn_result: std_logic;
begin
	o_ram_write <= r_ram_write;
	o_ram_address <= r_ram_address;
	o_ram_data <= r_ram_data_out;

	o_dev_active <= r_dev_active;
	o_dev_write <= r_dev_write;
	o_dev_address <= r_dev_address;
	o_dev_data <= r_dev_data_out;

	o_halted <= '1' when r_state = HALT else '0';

	w_pc_plus_1 <= std_logic_vector(unsigned(r_program_counter) + 1);

	brn_comp: comparator port map(
		i_operator => r_instruction(4 downto 3),
		i_value_0 => r_registers(0),
		i_value_1 => r_registers(1),
		o_result => w_brn_result
	);

	process(i_clock, i_reset)
	begin
		if i_reset = '1' then
			r_ram_write <= '0';
			r_ram_address <= (others => '0');
			r_ram_data_out <= (others => '0');

			r_dev_active <= '0';
			r_dev_write <= '0';
			r_dev_address <= (others => '0');
			r_dev_data_out <= (others => '0');

			r_registers <= (others => (others => '0'));
			r_program_counter <= (others => '0');
			r_instruction <= (others => '0');
			r_mov_offset <= (others => '0');
			r_state <= FETCH;
		else
			r_ram_write <= r_ram_write;
			r_ram_address <= r_ram_address;
			r_ram_data_out <= r_ram_data_out;

			r_dev_active <= r_dev_active;
			r_dev_write <= r_dev_write;
			r_dev_address <= r_dev_address;
			r_dev_data_out <= r_dev_data_out;

			r_registers <= r_registers;
			r_program_counter <= r_program_counter;
			r_instruction <= r_instruction;
			r_mov_offset <= r_mov_offset;
			r_state <= r_state;

			if rising_edge(i_clock) and r_state /= HALT and i_enable = '1' then
				case r_state is
					when FETCH =>
						r_ram_write <= '0';
						r_ram_address <= r_program_counter;
						r_state <= DECODE;
					when DECODE =>
						r_instruction <= i_ram_data;
						r_state <= RUN;
						if i_ram_data = "00100000" then
							r_state <= HALT;
						else
							case i_ram_data(7 downto 5) is
								when "000" => -- NIL
									null;
								when "001" => -- HLT
									null;
								when "010" => -- JMP
									null;
								when "011" => -- MOV
									r_ram_address <= std_logic_vector(
										unsigned(i_ram_data(2 downto 0)) + unsigned(r_mov_offset)
									);
									r_ram_write <= i_ram_data(4);
									-- The input data is ignored when reading
									r_ram_data_out <= r_registers(to_integer(unsigned(i_ram_data(3 downto 3))));
								when "100" => -- DAT
									if i_ram_data(0) = '1' then
										r_ram_write <= '0';
										r_ram_address <= std_logic_vector(unsigned(r_program_counter) + 2);
									end if;
								when "101" => -- OPR
									null;
								when "110" => -- BRN
									null;
								when "111" => -- SPC
									-- TODO
									r_state <= HALT;
								when others => -- Unknown instruction state
									r_state <= HALT;
							end case;
						end if;
					when RUN =>
						-- By default, move on to the next instruction.
						r_program_counter <= w_pc_plus_1;
						r_state <= FETCH;
						case r_instruction(7 downto 5) is
							when "000" => -- NIL
								null;
							when "001" => -- HLT
								-- NOTE: This is not reached if already 0.
								if r_instruction /= "00100001" then
									-- TODO: fix this: it is currently too fast
									r_instruction <= std_logic_vector(unsigned(r_instruction) - 1);
									r_program_counter <= r_program_counter;
									r_state <= RUN;
								end if;
							when "010" => -- JMP
								if r_instruction(4) = '1' then
									r_program_counter <= std_logic_vector(
										unsigned(r_program_counter) + unsigned(r_instruction(3 downto 0))
									);
								else
									r_program_counter <= std_logic_vector(
										unsigned(r_program_counter) - unsigned(r_instruction(3 downto 0))
									);
								end if;
							when "011" => -- MOV
								if r_instruction(4) = '0' then
									-- It was a read operation; save the result
									r_registers(to_integer(unsigned(r_instruction(3 downto 3)))) <= i_ram_data;
								end if;
							when "100" => -- DAT
								if r_instruction(0) = '1' then
									r_dev_data_out <= i_ram_data;
								elsif r_instruction(4) = r_instruction(1) then
									r_dev_data_out <= r_registers(1);
								else
									r_dev_data_out <= r_registers(0);
								end if;
								r_dev_write <= r_instruction(4);
								r_dev_address <= r_instruction(3 downto 2);
								r_dev_active <= '1';
								r_program_counter <= r_program_counter;
								r_state <= DAT_DONE;
							when "101" => -- OPR
								case i_ram_data(4 downto 0) is
									when "00000" => -- sub: r0 -= r1
										r_registers(0) <= std_logic_vector(signed(r_registers(0)) - signed(r_registers(1)));
									when "00001" => -- add: r0 += r1
										r_registers(0) <= std_logic_vector(signed(r_registers(0)) + signed(r_registers(1)));
									when "00010" => -- div: r0 /= r1
										r_state <= HALT; -- TODO
									when "00011" => -- mul: r0 *= r1
										r_state <= HALT; -- TODO
									when "00100" => -- copy: r1 = r0
										r_registers(1) <= r_registers(0);
									when "00101" => -- copy: r0 = r1
										r_registers(0) <= r_registers(1);
									when "00110" => -- mod: r0 %= r1 (remainder?)
										r_state <= HALT; -- TODO
									when "00111" => -- exp: r0 = r0 ^ r1
										r_state <= HALT; -- TODO
									when "01000" => -- jump: PC = r0
										r_program_counter <= r_registers(0);
									when "01001" => -- jump: PC = r1
										r_program_counter <= r_registers(1);
									when "01010" => -- offset = r0
										r_mov_offset <= r_registers(0);
									when "01011" => -- offset = PC
										r_mov_offset <= r_program_counter;
									when "01100" => -- set: r0 = 0
										r_registers(0) <= "00000000";
									when "01101" => -- set: r0 = 1
										r_registers(0) <= "00000001";
									when "01110" => -- set: r1 = 0
										r_registers(1) <= "00000000";
									when "01111" => -- set: r1 = 1
										r_registers(1) <= "00000001";
									when "10000" => -- set: r0 = 2
										r_registers(0) <= "00000010";
									when "10001" => -- set: r0 = 3
										r_registers(0) <= "00000011";
									when "10010" => -- set: r1 = 2
										r_registers(1) <= "00000010";
									when "10011" => -- set: r1 = 3
										r_registers(1) <= "00000011";
									when "10100" => -- shift: r0 = r0 << r1 (or >> ?)
										r_registers(0) <= std_logic_vector(shift_left(
											signed(r_registers(0)),
											to_integer(signed(r_registers(1)))
										));
									when "10101" => -- shift: r1 = r1 << r0 (or >> ?)
										r_registers(1) <= std_logic_vector(shift_left(
											signed(r_registers(1)),
											to_integer(signed(r_registers(0)))
										));
									when others => -- undefined
										r_state <= HALT;
								end case;
							when "110" => -- BRN
								if w_brn_result = '1' then
									r_program_counter <= std_logic_vector(
										unsigned(w_pc_plus_1) + 1 + unsigned(r_instruction(2 downto 0))
									);
								end if;
							when "111" => -- SPC
								-- TODO
								r_state <= HALT;
							when others => -- Unknown instruction state
								r_state <= HALT;
						end case;
					when DAT_DONE =>
						r_dev_active <= '0';
						if r_instruction(4) = '0' then
							r_registers(to_integer(unsigned(r_instruction(1 downto 1)))) <= i_dev_data;
						end if;
						r_program_counter <= w_pc_plus_1;
						r_state <= FETCH;
					when others =>
						r_state <= HALT;
				end case;
			end if;
		end if;
	end process;
end cpu_arch;
