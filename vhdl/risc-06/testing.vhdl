library ieee;
use ieee.std_logic_1164.all;

entity test_tb is
end test_tb;

architecture test_tb_arch of test_tb is
	component top is
		port(
			i_clock: in std_logic;
			i_reset: in std_logic
		);
	end component top;

	signal r_reset: std_logic := '1';
	signal r_clock: std_logic := '0';
begin
	my_top: top
	port map (
		i_reset => r_reset,
		i_clock => r_clock
	);

	process (*)
	begin
		while true loop
			r_clock <= '0';
			wait for 10ns;
			r_clock <= '1';
			wait for 10ns;
		end loop;
	end process;

	process (*)
		r_reset <= '1';
		wait for 100ns;
		r_reset <= '0';
	end process;
end test_tb_arch;
