library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- NOTE: This was build by the spec, and so has disk on port 0, monitor on 1.
-- The posted code and gif appears to show that it is actually the opposite.

entity top is
	port(
		i_clock: in std_logic;
		i_reset: in std_logic
	);
end top;

architecture top_arch of top is
	component cpu is
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
	end component cpu;
	component ram is
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
	end component ram;
	component disk_device is
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
	end component disk_device;
	component monitor_16x8x1_device is
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
	end component monitor_16x8x1_device;

	-- For connecting the CPU to the main memory RAM
	signal w_ram_write: std_logic;
	signal w_ram_address: std_logic_vector(7 downto 0);
	signal w_ram_data_in: std_logic_vector(7 downto 0);
	signal w_ram_data_out: std_logic_vector(7 downto 0);

	-- For connecting the CPU to the devices
	signal w_dev_is_active: std_logic;
	signal w_dev_write: std_logic;
	signal w_dev_address: std_logic_vector(1 downto 0);
	signal w_dev_active: std_logic_vector(3 downto 0);
	type dev_data_out_type is array(3 downto 0) of std_logic_vector(7 downto 0);
	signal w_dev_data_out: dev_data_out_type;
	signal w_dev_data_in: std_logic_vector(7 downto 0);

	-- For connecting the disk device to its backing RAM
	signal w_disk_ram_write: std_logic;
	signal w_disk_ram_address: std_logic_vector(7 downto 0);
	signal w_disk_ram_data_out: std_logic_vector(7 downto 0);
	signal w_disk_ram_data_in: std_logic_vector(7 downto 0);

	-- For connecting the monitor device to its backing RAM
	signal w_monitor_ram_write: std_logic;
	signal w_monitor_ram_address: std_logic_vector(3 downto 0);
	signal w_monitor_ram_data_out: std_logic_vector(7 downto 0);
	signal w_monitor_ram_data_in: std_logic_vector(7 downto 0);
begin
	processor: cpu
	port map (
		i_reset => i_reset,
		i_clock => i_clock,
		i_enable => '1',
		o_halted => open,

		o_ram_write => w_ram_write,
		o_ram_address => w_ram_address,
		o_ram_data => w_ram_data_in,
		i_ram_data => w_ram_data_out,

		o_dev_active => w_dev_is_active,
		o_dev_write => w_dev_write,
		o_dev_address => w_dev_address,
		o_dev_data => w_dev_data_in,
		i_dev_data => w_dev_data_out(to_integer(unsigned(w_dev_address)))
	);

	-- main memory for the system : 32 bytes of RAM
	main_memory: ram
	generic map (
		g_address_bits => 5
	) port map (
		i_clock => i_clock,
		i_address => w_ram_address(4 downto 0),
		i_write => w_ram_write,
		i_data => w_ram_data_in,
		o_data => w_ram_data_out
	);

	-- decoder for which device, if any, is currently active
	w_dev_active <= (others => '0') when w_dev_is_active /= '1' else
		"0001" when w_dev_address = "00" else
		"0010" when w_dev_address = "01" else
		"0100" when w_dev_address = "10" else
		"1000" when w_dev_address = "11" else
		"0000";

	-- device 0 is a disk drive with 256 bytes of disk space
	device_0: disk_device
	port map (
		i_reset => i_reset,
		i_clock => i_clock,

		i_dev_active => w_dev_active(0),
		i_dev_write => w_dev_write,
		i_dev_data => w_dev_data_in,
		o_dev_data => w_dev_data_out(0),

		o_ram_write => w_disk_ram_write,
		o_ram_address => w_disk_ram_address,
		o_ram_data => w_disk_ram_data_in,
		i_ram_data => w_disk_ram_data_out
	);

	-- backing memory for the disk drive device : 256 bytes of RAM
	disk_content: ram
	generic map (
		g_address_bits => 8
	) port map (
		i_clock => i_clock,
		i_address => w_disk_ram_address,
		i_write => w_disk_ram_write,
		i_data => w_disk_ram_data_in,
		o_data => w_disk_ram_data_out
	);

	-- device 1 is a monochrome monitor with 16x8 pixels
	device_1: monitor_16x8x1_device
	port map (
		i_reset => i_reset,
		i_clock => i_clock,

		i_dev_active => w_dev_active(1),
		i_dev_write => w_dev_write,
		i_dev_data => w_dev_data_in,
		o_dev_data => w_dev_data_out(1),

		o_ram_write => w_monitor_ram_write,
		o_ram_address => w_monitor_ram_address,
		o_ram_data => w_monitor_ram_data_in,
		i_ram_data => w_monitor_ram_data_out
	);

	-- video memory for the monitor device : 16 bytes of RAM
	monitor_video_memory: ram
	generic map (
		g_address_bits => 4
	) port map (
		i_clock => i_clock,
		i_address => w_monitor_ram_address,
		i_write => w_monitor_ram_write,
		i_data => w_monitor_ram_data_in,
		o_data => w_monitor_ram_data_out
	);

	-- device 2 is not connected
	w_dev_data_out(2) <= (others => '0');

	-- device 3 is not connected
	w_dev_data_out(3) <= (others => '0');
end top_arch;
