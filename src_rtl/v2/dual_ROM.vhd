library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity dual_ROM is
    Port ( Addr_a : in STD_LOGIC_VECTOR (4 downto 0);
           Addr_b : in STD_LOGIC_VECTOR (4 downto 0);
           Dout_a : out STD_LOGIC_VECTOR (15 downto 0);
           Dout_b : out STD_LOGIC_VECTOR (15 downto 0));
end dual_ROM;

architecture dataflow of dual_ROM is
Signal temp_addr_a: std_logic_vector (4 downto 0) := (others => '0');
Signal temp_addr_b: std_logic_vector (4 downto 0) := (others => '0');

TYPE vector_array IS ARRAY (0 to 31) OF STD_LOGIC_VECTOR  (15 DOWNTO 0);
-- memory for rc
CONSTANT memory_a : vector_array := (
0 => X"0f47", 1=> X"04b2", 2=> X"43b5", 3=> X"f137", 4=> X"4496", 5=> X"73ee",
6 => X"e54c", 7 => X"0bf5", 8 => X"4707", 9 => X"b282" , 10 => X"b5a1", 11 => X"3778", 
12 => X"96a2", 13 => X"eeb9", 14 => X"4cf2", 15 => X"f585", 16 => X"0723", 17 => X"82d9",
others => X"0000"
);

-- memory for SC
CONSTANT memory_b : vector_array := (
0 => X"0864", 1=> X"866b", 2=> X"e26f", 3=> X"892c", 4=> X"e6dd", 5=> X"ca99",
6 => X"17ea", 7 => X"8e0f", 8 => X"6404", 9 => X"6b43" , 10 => X"6ff1", 11 => X"2c44", 
12 => X"dd73", 13 => X"99e5", 14 => X"ea0b", 15 => X"0f47", 16 => X"04b2", 17 => X"43b5",
others => X"0000"
);

begin

temp_addr_a <=  Addr_a;
temp_addr_b <=  Addr_b;

Dout_a <= memory_a(TO_INTEGER(unsigned(temp_addr_a)));
Dout_b <= memory_b(TO_INTEGER(unsigned(temp_addr_b)));

end dataflow;
