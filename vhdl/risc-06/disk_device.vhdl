library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity disk_device is
	generic(
		g_data_bits: positive := 8
	);
	port(
		i_reset: in std_logic;
		i_clock: in std_logic;

		i_dev_active: in std_logic;
		i_dev_write: in std_logic;
		i_dev_data: in std_logic_vector(g_data_bits - 1 downto 0);
		o_dev_data: out std_logic_vector(g_data_bits - 1 downto 0);

		o_ram_write: out std_logic;
		o_ram_address: out std_logic_vector(g_data_bits - 1 downto 0);
		o_ram_data: out std_logic_vector(g_data_bits - 1 downto 0);
		i_ram_data: in std_logic_vector(g_data_bits - 1 downto 0)
	);
end disk_device;

architecture disk_device_arch of disk_device is
	signal r_write_address: std_logic_vector(g_data_bits - 1 downto 0);
	signal r_has_write_address: std_logic;
begin
	-- Only matters for READ operations. For non-FPGA, maybe 'Z' if !i_dev_active.
	o_dev_data <= i_ram_data;
	-- For READ operations, i_dev_data is the address to read from
	o_ram_address <= r_write_address when i_dev_write = '1' else i_dev_data;
	-- Only matters when o_ram_write is 1, so only when writing the given data.
	o_ram_data <= i_dev_data;
	-- Only 1 when we are writing data to RAM.
	o_ram_write <= '1' when i_reset = '0' and i_dev_active = '1' and i_dev_write = '1' and r_has_write_address = '1' else '0';

	process (i_clock, i_reset)
	begin
		if i_reset = '1' then
			r_has_write_address <= '0';
			r_write_address <= (others => '0');
		else
			r_has_write_address <= r_has_write_address;
			r_write_address <= r_write_address;

			if rising_edge(i_clock) and i_dev_write = '1' and i_dev_active = '1' then
				if r_has_write_address = '1' then
					r_has_write_address <= '0';
				else
					r_write_address <= i_dev_data;
					r_has_write_address <= '1';
				end if;
			end if;
		end if;
	end process;
end disk_device_arch;
