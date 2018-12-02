library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity comparator is
	port(
		i_operator: in std_logic_vector(1 downto 0);
		i_value_0: in std_logic_vector(7 downto 0);
		i_value_1: in std_logic_vector(7 downto 0);
		o_result: out std_logic
	);
end comparator;

architecture comparator_arch of comparator is
	signal w_eq, w_ne, w_gt, w_lt: std_logic;
begin
	w_eq <= '1' when i_value_0 = i_value_1 else '0';
	w_ne <= '1' when i_value_0 /= i_value_1 else '0';
	w_gt <= '1' when signed(i_value_0) > signed(i_value_1) else '0';
	w_lt <= '1' when signed(i_value_0) < signed(i_value_1) else '0';
	o_result <=
		w_eq when i_operator = "00" else
		w_ne when i_operator = "01" else
		w_gt when i_operator = "10" else
		w_lt when i_operator = "11" else
		'0';
end comparator_arch;
