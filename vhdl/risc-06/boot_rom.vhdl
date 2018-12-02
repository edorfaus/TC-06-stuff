library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity boot_rom is
	generic(
		g_address_bits: positive := 5;
		g_data_bits: positive := 8
	);
	port(
		i_address: in std_logic_vector(g_address_bits - 1 downto 0);
		o_data: out std_logic_vector(g_data_bits - 1 downto 0)
	);
end boot_rom;

architecture boot_rom_arch of boot_rom is
	type rom_data is array(0 to (2 ** g_address_bits) - 1)
		of std_logic_vector(g_data_bits - 1 downto 0);
	constant rom_content: rom_data := (
		"10010100", -- DAT 1 1 0 0  //ADR00
		"10010101", -- DAT 1 1 0 1  //ADR01
		"01000010", -- JMP 0 2      //ADR03
		"10001001", -- DTC 10001001 //ADR04
		"10101101", -- OPR 6 1      //ADR05
		"10010100", -- DAT 1 1 0 0  //ADR06
		"10010101", -- DAT 1 1 0 1  //ADR07
		"01000010", -- JMP 0 2      //ADR08
		"00001001", -- DTC 00001001 //ADR09
		"10101100", -- OPR 6 0      //ADR10-LOOPS
		"10000110", -- DAT 0 1 1 0  //ADR11
		"10010010", -- DAT 1 0 1 0  //ADR12
		"10101101", -- OPR 6 1      //ADR13
		"10000110", -- DAT 0 1 1 0  //ADR14
		"10010010", -- DAT 1 0 1 0  //ADR15
		"01010110", -- JMP 1 6      //ADR16-LOOPE
		others => "00000000"
	);
begin
	o_data <= rom_content(to_integer(unsigned(i_address)));
end boot_rom_arch;
