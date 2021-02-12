----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/17/2020 10:23:21 PM
-- Design Name: 
-- Module Name: SB_64 - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity SB_64 is
    Port ( X_in  : in STD_LOGIC_VECTOR (63 downto 0);   -- input 64 bit state
           rc    : in STD_LOGIC_VECTOR (7 downto 0);    -- round constant rc0 or rc1
           X_New : out STD_LOGIC_VECTOR (63 downto 0)); -- output 64 bit state
end SB_64;

architecture dataflow of SB_64 is
type ARR7 is array (0 to 7) of std_logic_vector(31 downto 0);
type ARR8 is array (0 to 8) of std_logic_vector(31 downto 0);
SIGNAL xr_new: ARR8;
SIGNAL xr: ARR8;

SIGNAL x_left5:  ARR7;
SIGNAL x_left1:  ARR7;
SIGNAL x_midxor: ARR7;

begin

    xr(0) <= X_in(63 downto 32);
    xr_new(0) <= X_in (31 downto 0);
    
    Sbox_loop: for itr in 0 to 7 GENERATE
 
        x_left5(itr)  <= STD_LOGIC_VECTOR( rotate_left(Unsigned(xr(itr)), 5));
        x_left1(itr)  <= STD_LOGIC_VECTOR( rotate_left(Unsigned(xr(itr)), 1));
        x_midxor(itr) <= (x_left5(itr) and xr(itr)) XOR x_left1(itr);
        
        xr(itr+1)   <= x_midxor(itr) XOR xr_new(itr) XOR (((31 downto 1 => '1') & rc(itr)));
        xr_new(itr+1) <= xr(itr);        
    
    end GENERATE Sbox_loop;

    X_new(31 downto 0)  <= xr_new(8); -- produced output
    X_new(63 downto 32) <= xr(8); -- produced output

end dataflow;
