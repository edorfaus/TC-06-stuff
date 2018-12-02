library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram is
	generic(
		g_address_bits: positive;
		g_data_bits: positive := 8
	);
	port(
		i_clock: in std_logic;
		i_address: in std_logic_vector(g_address_bits - 1 downto 0);
		i_write: in std_logic;
		i_data: in std_logic_vector(g_data_bits - 1 downto 0);
		o_data: out std_logic_vector(g_data_bits - 1 downto 0)
	);
end ram;

architecture ram_arch of ram is
	type memory_type is array((2 ** g_address_bits) - 1 downto 0)
		of std_logic_vector(g_data_bits - 1 downto 0);
	signal r_memory: memory_type;
begin
	o_data <= i_data when i_write = '1' else r_memory(to_integer(unsigned(i_address)));
	process (i_clock)
	begin
		if rising_edge(i_clock) then
			r_memory(to_integer(unsigned(i_address))) <= i_data;
		end if;
	end process;
end ram_arch;
