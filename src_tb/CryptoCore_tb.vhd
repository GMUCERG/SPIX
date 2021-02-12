----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 12/16/2020 07:24:46 PM
-- Design Name: 
-- Module Name: CryptoCore_tb - Behavioral
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
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;
use work.NIST_LWAPI_pkg.all;
use work.design_pkg.all;
use std.env.finish;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity CryptoCore_tb is
--    Port ()
end CryptoCore_tb;

architecture Behavioral of CryptoCore_tb is

CONSTANT clock_period: time := 10 ns;

Component CryptoCore Port(
        clk             : in   STD_LOGIC;
        rst             : in   STD_LOGIC;
        --PreProcessor===============================================
        ----!key----------------------------------------------------
        key             : in   STD_LOGIC_VECTOR (CCSW     -1 downto 0);
        key_valid       : in   STD_LOGIC;
        key_ready       : out  STD_LOGIC;
        ----!Data----------------------------------------------------
        bdi             : in   STD_LOGIC_VECTOR (CCW     -1 downto 0);
        bdi_valid       : in   STD_LOGIC;
        bdi_ready       : out  STD_LOGIC;
        bdi_pad_loc     : in   STD_LOGIC_VECTOR (CCWdiv8 -1 downto 0);
        bdi_valid_bytes : in   STD_LOGIC_VECTOR (CCWdiv8 -1 downto 0);
        bdi_size        : in   STD_LOGIC_VECTOR (3       -1 downto 0);
        bdi_eot         : in   STD_LOGIC;
        bdi_eoi         : in   STD_LOGIC;
        bdi_type        : in   STD_LOGIC_VECTOR (4       -1 downto 0);
        decrypt_in      : in   STD_LOGIC;
        key_update      : in   STD_LOGIC;
        hash_in         : in   std_logic;
        --!Post Processor=========================================
        bdo             : out  STD_LOGIC_VECTOR (CCW     -1 downto 0);
        bdo_valid       : out  STD_LOGIC;
        bdo_ready       : in   STD_LOGIC;
        bdo_type        : out  STD_LOGIC_VECTOR (4       -1 downto 0);
        bdo_valid_bytes : out  STD_LOGIC_VECTOR (CCWdiv8 -1 downto 0);
        end_of_block    : out  STD_LOGIC;
        msg_auth_valid  : out  STD_LOGIC;
        msg_auth_ready  : in   STD_LOGIC;
        msg_auth        : out  STD_LOGIC
    );
    end component;

 -- signals 
    SIGNAL clk : STD_LOGIC;
    SIGNAL reset : STD_LOGIC := '1';
    -- user signals
   -- signals
    Signal key_tb          :    STD_LOGIC_VECTOR (CCSW     -1 downto 0);
    Signal    key_valid_tb       :    STD_LOGIC;
    Signal    key_ready       :    STD_LOGIC;
        ----!Data----------------------------------------------------
    Signal    bdi_tb             :    STD_LOGIC_VECTOR (CCW     -1 downto 0):= (others => '0');
    Signal    bdi_valid_tb       :    STD_LOGIC;
    Signal    bdi_ready       :    STD_LOGIC;
    Signal    bdi_pad_loc     :    STD_LOGIC_VECTOR (CCWdiv8 -1 downto 0);
    Signal    bdi_valid_bytes :    STD_LOGIC_VECTOR (CCWdiv8 -1 downto 0);
    Signal    bdi_size        :    STD_LOGIC_VECTOR (3       -1 downto 0);
    Signal    bdi_eot_tb         :    STD_LOGIC;
    Signal    bdi_eoi         :    STD_LOGIC;
    Signal    bdi_type_tb        :    STD_LOGIC_VECTOR (4       -1 downto 0);
    Signal    decrypt_in_tb      :    STD_LOGIC;
    Signal    key_update_tb      :    STD_LOGIC;
    Signal    hash_in         :    std_logic;
        --!Post Processor=========================================
    Signal    bdo             :   STD_LOGIC_VECTOR (CCW     -1 downto 0);
    Signal    bdo_valid       :   STD_LOGIC;
    Signal    bdo_ready_tb       :   STD_LOGIC;
    Signal    bdo_type        :   STD_LOGIC_VECTOR (4       -1 downto 0);
    Signal    bdo_valid_bytes :   STD_LOGIC_VECTOR (CCWdiv8 -1 downto 0);
    Signal    end_of_block    :   STD_LOGIC;
    Signal    msg_auth_valid  :   STD_LOGIC;
    Signal    msg_auth_ready_tb  :   STD_LOGIC;
    Signal    msg_auth        :   std_logic;
    
    -- State signals
TYPE state_t is (   S_Start,
                    S_Output_Key,
                    S_output_Nonce,
                    S_output_AD,
                    S_output_MSG,
                    S_recieve_tag,
                    S_Done);
                    
SIGNAL next_tb_state, current_tb_state           : state_t := S_Start;
    
    
    Signal key_test_vector: STD_LOGIC_VECTOR (127 downto 0)  := X"00111122335588DD00111122335588DD";--X"00000000000000000000000000000000";--
    Signal Npub_test_vector: STD_LOGIC_VECTOR (127 downto 0) := X"111122335588DD00111122335588DD00";--X"00000000000000000000000000000000";--
    
    Signal AD_test_vector: STD_LOGIC_VECTOR (127 downto 0)   := X"1122335588DD00111122335588DD0000";--X"00000000000000000000000000000000";--
    Signal PT_test_vector: STD_LOGIC_VECTOR (127 downto 0)   := X"335588DD00111122335588DD00111100";--X"00000000000000000000000000000000";--
    Signal count_tb: INTEGER := 0;
    Signal count_out: INTEGER := 0;
    
    Signal output_vector : STD_LOGIC_VECTOR (127 downto 0) := (others => '0');
    Signal output_tag_vector : STD_LOGIC_VECTOR (127 downto 0) := (others => '0');
    
begin

uut: entity work.CryptoCore PORT MAP (
        clk => clk,
        rst => reset,
        --PreProcessor===============================================
        ----!key----------------------------------------------------
        key             =>  key_tb,
        key_valid       =>  key_valid_tb, 
        key_ready       =>  key_ready,
        ----!Data----------------------------------------------------
        bdi             =>  bdi_tb, 
        bdi_valid       =>  bdi_valid_tb,
        bdi_ready       =>  bdi_ready,
        bdi_pad_loc     =>  bdi_pad_loc,
        bdi_valid_bytes =>  bdi_valid_bytes ,
        bdi_size        =>  bdi_size        ,
        bdi_eot         =>  bdi_eot_tb      ,
        bdi_eoi         =>  bdi_eoi         ,
        bdi_type        =>  bdi_type_tb     ,
        decrypt_in      =>  decrypt_in_tb   ,
        key_update      =>  key_update_tb   ,
        hash_in         =>  hash_in         ,
        --!Post Processoor                  ,
        bdo             =>  bdo             ,
        bdo_valid       =>  bdo_valid       ,
        bdo_ready       =>  bdo_ready_tb    ,
        bdo_type        =>  bdo_type        ,
        bdo_valid_bytes =>  bdo_valid_bytes ,
        end_of_block    =>  end_of_block    ,
        msg_auth_valid  =>  msg_auth_valid  ,
        msg_auth_ready  =>  msg_auth_ready_tb,
        msg_auth        =>  msg_auth       
        );
    
    Clock_Generator: PROCESS
    BEGIN
        clk <='1';
        WAIT FOR clock_period/2; -- low for 5 ns
        clk <='0';
        WAIT FOR clock_period/2; -- high for 5 ns
    END PROCESS;

    State_register: process(clk, reset)
        begin
        if (reset ='1') then
            current_tb_state <= S_Start;
        elsif rising_edge(clk) then
            current_tb_state <= next_tb_state;    
        end if;    
    end process State_register;

    tb_state : PROCESS
    BEGIN
        wait for clock_period;
        -- default values
        key_update_tb <= '0';
        key_valid_tb <= '0';
        bdi_type_tb <= (others => '0');
        bdi_valid_tb <= '0';
        decrypt_in_tb <= '0';
        bdi_eot_tb <= '0';
        bdo_ready_tb <= '0';
        reset <= '0';
        bdi_eoi <= '0';
        bdi_pad_loc <= std_logic_vector(to_unsigned(0, bdi_pad_loc'length));
        
        CASE current_tb_state IS
        ----------------- Reset state -----------------------------------
            WHEN S_Start =>
                next_tb_state <= S_Output_Key;
                count_tb <= 0;
                key_tb <= key_test_vector(127 downto ccw*3);
        ----------------- Output key state -----------------------------------   
            When S_Output_Key =>
                key_update_tb <= '1';
                key_valid_tb <= '0';
                
                if (key_ready ='1') then
                    if (count_tb = 0) then
                        key_tb <= key_test_vector(127 downto 96);
                        count_tb <= count_tb + 1;
                        key_valid_tb <= '1';
                    elsif (count_tb = 1) then
                        key_tb <= key_test_vector(95 downto 64);
                        count_tb <= count_tb + 1;
                        key_valid_tb <= '1';
                    elsif (count_tb = 2) then
                        key_tb <= key_test_vector(63 downto 32);    
                        count_tb <= count_tb + 1;
                        key_valid_tb <= '1';
                    elsif (count_tb = 3) then
                        key_tb <= key_test_vector(31 downto 0);
                        count_tb <= count_tb + 1;
                        key_valid_tb <= '1';
                    end if;   
                end if;
                
                if (count_tb = 4)  then
                    
                    key_update_tb <= '0';
                    if (bdi_ready = '1') then
                        next_tb_state <= S_output_Nonce;
                        count_tb <= 0;
                    wait for clock_period;
                end if;
            end if;
            
       ----------------- Output Npub state -----------------------------------   
            When S_output_Nonce =>      
                bdi_type_tb <= HDR_NPUB;
                bdi_valid_tb <= '0';
                
                if (bdi_ready ='1') then
                    if (count_tb = 0) then
                        bdi_tb <= Npub_test_vector(127 downto 96);
                        count_tb <= count_tb + 1;
                        bdi_valid_tb <= '1';
                    elsif (count_tb = 1) then
                        bdi_tb <= Npub_test_vector(95 downto 64);
                        count_tb <= count_tb + 1;
                        bdi_valid_tb <= '1';
                    elsif (count_tb = 2) then
                        bdi_tb <= Npub_test_vector(63 downto 32);
                        count_tb <= count_tb + 1;
                        bdi_valid_tb <= '1';
                    elsif (count_tb = 3) then
                        bdi_tb <= Npub_test_vector(31 downto 0);
                        count_tb <= count_tb + 1;
                        bdi_eot_tb <= '1';
                        bdi_valid_tb <= '1';
                    end if;
                    
                end if;
                
                if (count_tb = 4) then
                    next_tb_state <= S_output_AD;
                    count_tb <= 0;
                    wait for clock_period;
                end if;
                
       ----------------- Output AD state -----------------------------------   
            When S_output_AD =>      
                bdi_type_tb <= HDR_AD;
                
                
                if (bdi_ready ='1') then
                    if (count_tb = 0) then
                        bdi_tb <= AD_test_vector(127 downto ccw*3);
                        count_tb <= count_tb + 1;
                        bdi_valid_tb <= '1';
                    elsif (count_tb = 1) then
                        bdi_tb <= AD_test_vector(ccw*3-1 downto ccw*2);
                        count_tb <= count_tb + 1;
                        bdi_valid_tb <= '1';
                    elsif (count_tb = 2) then
                        bdi_tb <= AD_test_vector(ccw*2-1 downto ccw);
                        count_tb <= count_tb + 1;
                        bdi_valid_tb <= '1';
                    elsif (count_tb = 3) then
                        bdi_tb <= AD_test_vector(ccw-1 downto 0);
                        bdi_pad_loc <= std_logic_vector(to_unsigned(24, bdi_pad_loc'length));
                        bdi_eot_tb <= '1';
                        count_tb <= count_tb + 1;
                        bdi_valid_tb <= '1';
                    end if;
  
                end if;
                
                if (count_tb = 4) then
                    next_tb_state <= S_output_MSG;
                    count_tb <= 0;
                    wait for clock_period;
                end if;
                
       ----------------- Output and recieve Msg state -----------------------------------   
            When S_output_MSG =>      
                bdi_type_tb <= HDR_PT;
                bdo_ready_tb <= '1';
                
                if (bdi_ready ='1') then
                    if (count_tb = 0) then
                        bdi_tb <= PT_test_vector(127 downto ccw*3);
                        bdi_valid_tb <= '1';
                        count_tb <= count_tb + 1; 
                    elsif (count_tb = 1) then
                        bdi_tb <= PT_test_vector(ccw*3-1 downto ccw*2);
                        bdi_valid_tb <= '1';
                        count_tb <= count_tb + 1; 
                    elsif (count_tb = 2) then
                        bdi_tb <= PT_test_vector(ccw*2-1 downto ccw);
                        bdi_valid_tb <= '1';
                        count_tb <= count_tb + 1;  
                        bdi_eot_tb <= '1';   
                    elsif (count_tb = 3) then
                        bdi_tb <= PT_test_vector(ccw-1 downto 0);
                        bdi_pad_loc <= std_logic_vector(to_unsigned(24, bdi_pad_loc'length));
                        bdi_eot_tb <= '1';
                        count_tb <= count_tb + 1;
                        bdi_valid_tb <= '1';
                    end if;
                     
                end if;
                
                if ((bdo_valid ='1') and (bdo_type = HDR_CT)) then
                     if (count_out = 0) then
                        output_vector(127 downto 96) <= bdo ;
                        count_out <= count_out + 1;
                    elsif (count_out = 1) then
                         output_vector(95 downto 64) <= bdo ;
                         count_out <= count_out + 1;
                    elsif (count_out = 2) then
                         output_vector(63 downto 32) <= bdo ;
                         count_out <= count_out + 1;   
                    elsif (count_out = 3) then
                         output_vector(31 downto 0)  <= bdo ;
                    end if;    
                end if;
                
                if ( (count_tb = 4) and (count_out = 3)) then
                    count_tb <= 0;
                    count_out <= 0;
                    next_tb_state <= S_recieve_tag;
                    wait for clock_period;
                end if;
        
        ----------------- S_recieve_tag state -----------------------------------   
            When S_recieve_tag =>
                bdo_ready_tb <= '1';
                
                if ( (bdo_valid ='1') and (bdo_type=HDR_TAG)) then
                     if (count_out = 0) then
                        output_tag_vector(127 downto 96) <= bdo ;
                        count_out <= count_out + 1;
                    elsif (count_out = 1) then
                         output_tag_vector(95 downto 64) <= bdo ;
                         count_out <= count_out + 1;
                    elsif (count_out = 2) then
                         output_tag_vector(63 downto 32) <= bdo ;
                         count_out <= count_out + 1;   
                    elsif (count_out = 3) then
                         output_tag_vector(31 downto 0)  <= bdo ;
                    end if;    
                end if;
                
                if ( count_out = 3) then
                    count_out <= 0;
                    next_tb_state <= S_Done;
                end if;    
        
         ----------------- S_recieve_tag state -----------------------------------   
            When S_Done =>
                ---done testing
                finish;
        end Case;
        -- set key update
        
    end process tb_state;
end Behavioral;
