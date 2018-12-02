library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity monitor_16x8x1_device is
	port(
		i_reset: in std_logic;
		i_clock: in std_logic;

		i_dev_active: in std_logic;
		i_dev_write: in std_logic;
		i_dev_data: in std_logic_vector(7 downto 0);
		o_dev_data: out std_logic_vector(7 downto 0);

		o_ram_write: out std_logic;
		o_ram_address: out std_logic_vector(3 downto 0);
		o_ram_data: out std_logic_vector(7 downto 0);
		i_ram_data: in std_logic_vector(7 downto 0)
	);
end monitor_16x8x1_device;

architecture monitor_16x8x1_device_arch of monitor_16x8x1_device is
	type state_type is (READY, WRITE_DATA);
	signal r_state: state_type;
	signal r_write_address: std_logic_vector(3 downto 0);
	signal r_new_data: std_logic_vector(7 downto 0);
	signal w_read_data: std_logic;
begin
	o_ram_write <= '1' when r_state = WRITE_DATA else '0';
	o_ram_address <= r_write_address when r_state = WRITE_DATA else i_dev_data(6 downto 3);
	o_ram_data <= r_new_data;

	-- On read, bit 7 says whether to return the value or the entire command
	w_read_data <= i_ram_data(to_integer(unsigned(i_dev_data(2 downto 0))));
	o_dev_data <= (0 => w_read_data, others => '0') when i_dev_data(7) = '0' else (
			7 => w_read_data, 6 => i_dev_data(6), 5 => i_dev_data(5), 4 => i_dev_data(4),
			3 => i_dev_data(3), 2 => i_dev_data(2), 1 => i_dev_data(1), 0 => i_dev_data(0)
		);

	process (i_clock, i_reset)
	begin
		o_dev_data <= (others => '0');

		if i_reset = '1' then
			r_state <= READY;
			r_write_address <= (others => '0');
			r_new_data <= (others => '0');
		else
			r_state <= r_state;
			r_write_address <= r_write_address;
			r_new_data <= r_new_data;

			if rising_edge(i_clock) then
				case r_state is
					when READY =>
						if i_dev_active = '1' and i_dev_write = '1' then
							r_state <= WRITE_DATA;
							r_write_address <= i_dev_data(6 downto 3);

							r_new_data <= i_ram_data;
							case i_dev_data(2 downto 0) is
								when "000" => r_new_data(0) <= i_dev_data(7);
								when "001" => r_new_data(1) <= i_dev_data(7);
								when "010" => r_new_data(2) <= i_dev_data(7);
								when "011" => r_new_data(3) <= i_dev_data(7);
								when "100" => r_new_data(4) <= i_dev_data(7);
								when "101" => r_new_data(5) <= i_dev_data(7);
								when "110" => r_new_data(6) <= i_dev_data(7);
								when "111" => r_new_data(7) <= i_dev_data(7);
								when others => null;
							end case;
						end if;

					when WRITE_DATA =>
						r_state <= READY;
						-- The rest is handled by the combinatorics above

					when others =>
						r_state <= READY;
				end case;
			end if;
		end if;
	end process;
end monitor_16x8x1_device_arch;
