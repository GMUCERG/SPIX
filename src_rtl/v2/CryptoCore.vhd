--------------------------------------------------------------------------------
--! @file       CryptoCore.vhd
--! @brief      Template for CryptoCore implementations
--!
--! @author     Patrick Karl <patrick.karl@tum.de>
--! @copyright  Copyright (c) 2019 Chair of Security in Information Technology     
--!             ECE Department, Technical University of Munich, GERMANY
--!             All rights Reserved.
--! @license    This project is released under the GNU Public License.          
--!             The license and distribution terms for this file may be         
--!             found in the file LICENSE in this distribution or at            
--!             http://www.gnu.org/licenses/gpl-3.0.txt                         
--! @note       This is publicly available encryption source code that falls    
--!             under the License Exception TSU (Technology and software-       
--!             unrestricted)                                                  
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;
use work.NIST_LWAPI_pkg.all;
use work.design_pkg.all;


entity CryptoCore is
    Generic(G_ASYNC_RSTN : boolean:= false);
    Port (
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
        bdo             : out  STD_LOGIC_VECTOR (CCW      -1 downto 0);
        bdo_valid       : out  STD_LOGIC;
        bdo_ready       : in   STD_LOGIC;
        bdo_type        : out  STD_LOGIC_VECTOR (4       -1 downto 0);
        bdo_valid_bytes : out  STD_LOGIC_VECTOR (CCWdiv8 -1 downto 0);
        end_of_block    : out  STD_LOGIC;
        msg_auth_valid  : out  STD_LOGIC;
        msg_auth_ready  : in   STD_LOGIC;
        msg_auth        : out  STD_LOGIC
    );
end CryptoCore;

architecture mixed of CryptoCore is

-- bus lengths
constant r_width          : integer := 64;
constant r_half_width     : integer := r_width / 2;
constant c_width          : integer := r_width * 3;
constant key_size         : integer := 128;
constant tag_size         : integer := 128;
constant perm_size        : integer := 256;
constant round_const_size : integer := 16;
constant step_const_size  : integer := 16;

-- internal state signals
SIGNAL Sr, SrP                          : STD_LOGIC_VECTOR (r_width-1 downto 0);  -- rate part of S output of permutation
SIGNAL Sc, ScP                          : STD_LOGIC_VECTOR (c_width-1 downto 0);  -- capacity part of S output of permutation
SIGNAL x0, x1, x2, x3                   : STD_LOGIC_VECTOR (r_width-1 downto 0);  -- inputs of the permutation
SIGNAL x0perm, x1perm, x2perm, x3perm   : STD_LOGIC_VECTOR (r_width-1 downto 0); -- outputs of the permutation
SIGNAL x0_reg_in, x1_reg_in, x2_reg_in, x3_reg_in  : STD_LOGIC_VECTOR (r_width-1 downto 0):= (OTHERS=>'0'); -- register inputs
SIGNAL x0_reg_out, x1_reg_out, x2_reg_out, x3_reg_out  : STD_LOGIC_VECTOR (r_width-1 downto 0); -- register outputs
SIGNAL sb1_valid, sb3_valid : STD_LOGIC;
SIGNAL bdi_pad_loc_internal  : STD_LOGIC_VECTOR (CCWdiv8 -1 downto 0);
SIGNAL bdi_msg_type_internal : STD_LOGIC_VECTOR (3 downto 0);
-- output signal interface
SIGNAL bdi_ready_internal, key_ready_internal: STD_LOGIC;
SIGNAL end_of_block_internal                 : STD_LOGIC;
SIGNAL bdo_type_internal                     : STD_LOGIC_VECTOR (3 downto 0);
SIGNAL bdo_valid_internal                    : STD_LOGIC;
SIGNAl bdo_valid_bytes_internal : STD_LOGIC_VECTOR (CCWdiv8 -1 downto 0);
SIGNAL single_output                         : STD_LOGIC := '0';
SIGNAL last_output : STD_LOGIC;
--round and step constants' signals
SIGNAL rc_i                             : STD_LOGIC_VECTOR (round_const_size-1 downto 0); --round constant
SIGNAL rc_0, rc_1                       : STD_LOGIC_VECTOR (round_const_size/2-1 downto 0); -- blocks of the round constants

SIGNAL sc_i                             : STD_LOGIC_VECTOR (step_const_size-1 downto 0); --step constant
SIGNAL sc_0, sc_1                       : STD_LOGIC_VECTOR (step_const_size/2-1 downto 0); -- blocks of the round constants

-- counters' signals
SIGNAL i                                : STD_LOGIC_VECTOR (4 downto 0) := (others => '0');
SIGNAL count, current_count             : INTEGER;-- := 0; ---STD_LOGIC_VECTOR (1 downto 0) := (others => '0');
SIGNAL ldi, eni                         : STD_LOGIC := '0'; -- from the controller
SIGNAL zi18, zi17, zi9, Zblk1, Zblk2, Zblk3   : STD_LOGIC := '0'; -- to the controller

-- block counter
SIGNAL inc_count, reset_count           : STD_LOGIC := '0';
SIGNAL count_is_0, count_is_1, count_is_2, count_is_3, count_is_4 : STD_LOGIC := '0';

-- internal Key signals
SIGNAL K0, K1                           : STD_LOGIC_VECTOR (r_width-1 downto 0);  -- rate part of S output of permutation
SIGNAL Key_SIPO                         : STD_LOGIC_VECTOR (2*r_width-1 downto 0):= (others =>'0');  -- rate part of S output of permutation
SIGNAL Tag_in                           : STD_LOGIC_VECTOR (2*r_width-1 downto 0);  -- rate part of S output of permutation
-- input register signals
SIGNAL BDI_in                           : STD_LOGIC_VECTOR (r_width-1 downto 0):= (others =>'0');  --output of BDI input register
SIGNAL key_seg, BDO_out, BDO_reg_out    : STD_LOGIC_VECTOR (ccw-1 downto 0):= (others =>'0');  --output of key input register, BDO output
SIGNAL CT_reg : STD_LOGIC_VECTOR (63 downto 0):= (others =>'0');
SIGNAL enCT_reg : STD_LOGIC := '0';

SIGNAL BDI_in_dec                       : STD_LOGIC_VECTOR (r_width-1 downto 0):= (others =>'0');  --output of BDI input register

-- register enable signals
SIGNAL enBDI_SIPO, enKey_SIPO           : STD_LOGIC;    --input registers enable
SIGNAL enTagReg, decrypt_msg            : STD_LOGIC;    --Tag registers enable
SIGNAL enX0, enX1, enX2, enX3           : STD_LOGIC;    --internal state registers
SIGNAL enBDI_eot, last_block_type, last_block_input, rstBdi_eot       : STD_LOGIC := '0';   --used to preserve bdi_eot

SIGNAL bdi_buf, tag_buf                 : STD_LOGIC_VECTOR (ccw-1 downto 0);
-- mux select signals
SIGNAL new_perm,  pad_perm, pad_perm_reg, no_msg, no_msg_reg             : STD_LOGIC := '0';    --select for permutation mux
SIGNAL key_select, init_fin_select     : STD_LOGIC;
SIGNAL tag_ready_sel, processing_AD_sel: STD_LOGIC;
SIGNAL init, tag_ver                   : STD_LOGIC;

-- dataflow signals
SIGNAL key_select_out, init_fin_select_out : STD_LOGIC_VECTOR (r_width-1 downto 0);
SIGNAL x1p_left, x3p_left                  : STD_LOGIC_VECTOR (r_half_width-1 downto 0);
SIGNAL x1p_right, x3p_right                : STD_LOGIC_VECTOR (r_half_width-1 downto 0);
SIGNAL x0p, x1p, x2p, x3p, SrXorMux        : STD_LOGIC_VECTOR (r_width-1 downto 0);
SIGNAL pad_wire                            : STD_LOGIC_VECTOR (CCW-1 downto 0);
SIGNAL start_sb, done_sb1, done_sb2        : STD_LOGIC;
SIGNAL perm_is_9, perm_is_18               : STD_LOGIC;

-- output signals
SIGNAL T0, T1                              : STD_LOGIC_VECTOR (r_width-1 downto 0); -- 8 bytes
SIGNAL Tag_seg, Tag_in_seg                           : STD_LOGIC_VECTOR (ccw-1 downto 0); -- 4 bytes
SIGNAL bdo_seg                             : STD_LOGIC_VECTOR (ccw-1 downto 0):= (others => '0'); -- 4 bytes

-- Controller Signals
Signal ScXorConst                       : STD_LOGIC_VECTOR (1 downto 0);

-- State signals
TYPE state_t is (   S_WAITING,
                    S_STORE_KEY,
                    S_ABSORB_NONCE,
                    S_INIT_PERM18,
                    S_ABSORB_AD,
                    S_AD_PERM9,
                    S_ABSORB_MSG,
                    S_MSG_PERM9,
                    S_OUT_MSG,
                    S_FINAL_PERM18,
                    S_OUT_TAG,
                    S_ABSORB_TAG,
                    S_VERIFY_TagSeg);
                    
SIGNAL next_state, current_state           : state_t;

-- SimBox implementation
component SB64
     Port (clk      : in STD_LOGIC;
           rst      : in STD_LOGIC;
           start    : in STD_LOGIC;
           x_in     : in STD_LOGIC_VECTOR (63 downto 0);   -- input 64 bit state
           rc       : in STD_LOGIC_VECTOR (7 downto 0);    -- round constant rc0 or rc1
           x_out    : out STD_LOGIC_VECTOR (63 downto 0); -- output 64 bit state
           valid    : out STD_LOGIC);
end component;

-- Rom for Step and Round constants
component dual_ROM is
    Port ( Addr_a : in STD_LOGIC_VECTOR (4 downto 0);
           Addr_b : in STD_LOGIC_VECTOR (4 downto 0);
           Dout_a : out STD_LOGIC_VECTOR (15 downto 0);
           Dout_b : out STD_LOGIC_VECTOR (15 downto 0));
end component;

begin

------------------------------- State Machine ------------------------------------------------

----------------------------------------------------------------------------
--! Registers for state and internal signals
----------------------------------------------------------------------------
GEN_proc_SYNC_RST: if (not G_ASYNC_RSTN) generate
    process (clk)
    begin
        if rising_edge(clk) then
            if(rst='1')  then
                current_state <= S_WAITING;
                no_msg_reg    <= '0';
                pad_perm_reg  <= '0';
            else
                current_state <= next_state;
                pad_perm_reg <= pad_perm;
                no_msg_reg <= no_msg;
            end if;
        end if;
    end process;
end generate GEN_proc_SYNC_RST;
GEN_proc_ASYNC_RSTN: if (G_ASYNC_RSTN) generate
    process (clk, rst)
    begin
        if(rst='0')  then
            current_state <= S_WAITING;
            no_msg_reg    <= '0';
            pad_perm_reg  <= '0';
        elsif rising_edge(clk) then
            current_state <= next_state;
            pad_perm_reg  <= pad_perm;
            no_msg_reg    <= no_msg;
        end if;
    end process;
end generate GEN_proc_ASYNC_RSTN;

State_Control: process(current_state, key_update, key_valid, bdi_valid, bdi_type, bdi_eot, bdi_eoi, zi18, zi17, zi9,
                         decrypt_in, bdo_ready, last_block_type, msg_auth_ready, count_is_0, count_is_1, count_is_2, count_is_3, count_is_4, 
                         last_block_input, count, bdi_ready_internal, pad_perm_reg, bdi_msg_type_internal, bdi_valid_bytes, Tag_seg, Tag_in_seg,
                         no_msg_reg, bdi_pad_loc_internal, single_output, last_output)
begin
------------- default values for all control signals-----------
    --registers
    enKey_SIPO <= '0';
    enBDI_SIPO <= '0';
    enX0 <= '0'; enX1 <= '0'; enX2 <= '0'; enX3 <= '0';
    enBDi_eot <= '0';
    inc_count <= '0';
    reset_count <= '0';
    
    --counters
    --ldBlkCount <= '0'; -- set default
    --enBlkCount <= '0'; --increment the block counter
    ldi <= '0'; -- reset counter i
    eni <= '0'; -- reset counter i

    --output/control signals
    key_ready_internal <= '0';
    bdo_valid_internal <= '0';
    end_of_block_internal <= '0';
    bdi_ready_internal <= '0';
    bdo_type_internal <= "0000";
    ScXorConst <= "01";
    pad_wire <= std_logic_vector(to_unsigned(1, pad_wire'length));
    
    --mux signals
    init <= '0';
    new_perm <= '0';
    key_select <= '0';
    init_fin_select <= '0';
    processing_AD_sel <= '0';
    tag_ready_sel <= '0';
    
    msg_auth_valid <= '0';
    msg_auth       <= '0';
    next_state     <= current_state;
    rstBdi_eot     <= '0';
    pad_perm       <= pad_perm_reg;
    no_msg         <= no_msg_reg;
    enTagReg       <= '0';
    decrypt_msg    <= '0';
    enCT_reg <= '0';
    last_output <= '0';
    perm_is_9  <= '0';
    perm_is_18 <= '0';
    no_msg <= no_msg_reg;
       
    CASE current_state IS
    ----------------------------- WAITING -------------------------------------------
        WHEN S_WAITING =>
            enKey_SIPO <= '1';
            key_ready_internal <= '1'; -- indicate that the cryptoCore is ready to recieve the key
            reset_count <= '1';
            no_msg <= '0';
            pad_perm <= '0';
            
            if (key_update='1' and key_valid='1') then
                next_state <= S_STORE_KEY;
                inc_count <= '1';
                --enKey_SIPO <= '1'; --enable the key SIPO
            end if;
    
    ----------------------------- STORE KEY -------------------------------------------
        WHEN S_STORE_KEY =>
            enKey_SIPO <= '1';
            key_ready_internal <= '1'; -- indicate that the cryptoCore is ready to recieve the key
            init <= '1';
            
            --if (Zblk3 = '1') then
            if (count_is_3 = '1') then
                reset_count <= '1';
                key_ready_internal <= '0';
                
                next_state <= S_ABSORB_NONCE;
                enX1 <= '1';
                enX3 <= '1';
                new_perm <= '1';
              --end if;
            else
                if (key_valid = '1') then
                    --enKey_SIPO <= '1'; --enable the key SIPO
                    inc_count <= '1';
                end if;
            end if;
            
    ----------------------------- ABSORB NONCE -------------------------------------------
        WHEN S_ABSORB_NONCE =>
            init <= '1';
            bdi_ready_internal <= '1';
            enBDI_SIPO <= '1';
            
            enBDi_eot <= '1';
            if (last_block_input = '1') then
                enBDi_eot <= '0';
            end if;
            
            if (count_is_4 = '1') then
                reset_count <= '1';
                enX2 <= '1';
                bdi_ready_internal <= '1';
                new_perm <= '1';
                enBDI_SIPO <= '1';
                next_state <= S_INIT_PERM18;
            elsif (count_is_3 = '1') then
                bdi_ready_internal <= '0';    
            elsif (count_is_2 ='1') then
                new_perm <= '1';
                enX0 <= '1';
            end if;
            
            if (bdi_valid = '1' and bdi_type=HDR_NPUB and count_is_4 = '0') then
                 inc_count <= '1';
            end if;
            
      ----------------------------- S_INIT_PERM18 -------------------------------------------
        WHEN S_INIT_PERM18 =>
            perm_is_18 <= '1';
            if (bdi_eoi = '1') then
                enBDI_SIPO <= '1';
            end if;

            init_fin_select <= '1';
            enX0      <= '1';
            enX1      <= '1';
            enX2      <= '1';
            enX3      <= '1';            
            enBDi_eot <= '1';
            
            if (last_block_input = '1') then
                enBDi_eot <= '0';
            end if;
            
            if ((zi18 = '1') and count_is_2 = '1') then --zi17 = '1' or 
                enX0 <= '0';
                enX1 <= '0';
                enX2 <= '0';
                enX3 <= '0';
            end if;
            
            if (zi18 = '1') then --check if done with current permutation ||  or (zi17 = '1' and count_is_1 = '1')
                --if zBlk2 = '1' then --check for 3rd permutation stage
                if (count_is_2 = '1') then 
                    ldi         <= '1'; -- reset counter i
                    reset_count <= '1'; -- reset block counter
                    enBDi_eot   <= '0';

                    if ((last_block_input = '1' and bdi_msg_type_internal = HDR_NPUB) or (bdi_msg_type_internal = HDR_TAG)) then
                        -- last message was part of nonce
                        ScXorConst        <= "10";
                        processing_AD_sel <= '1';
                        init_fin_select   <= '0';
                        new_perm          <= '1';
                        ldi               <= '1';
                        
                        enX0 <= '1';
                        enX1 <= '1';
                        enX2 <= '1';
                        enX3 <= '1';  
                        next_state <= S_MSG_PERM9;  --go to the next state
                        no_msg     <= '1';
                    elsif (bdi_msg_type_internal = HDR_PT or bdi_msg_type_internal = HDR_CT) then
                        -- last message was part of nonce
                        next_state <= S_ABSORB_MSG;
                    else
                        next_state <= S_ABSORB_AD;
                    end if;
                else
                    if (count_is_0 = '1') then
                        key_select <= '0'; --use K0
                    else
                        key_select <= '1'; --use K1
                    end if;
              
                    new_perm <= '1';
                    ldi <= '1';            --reset counter i
                    inc_count <= '1';     --increment stage counter                   
                end if;
            else -- keep looping inside the permutation
                eni <= '1'; --increment i perm counter            
            end if;

     ----------------------------- S_ABSORB_AD -------------------------------------------
         WHEN S_ABSORB_AD =>
            perm_is_9 <= '1';
            ScXorConst         <= "01";
            bdi_ready_internal <= '1';
            enBDi_eot          <= '1'; 
            enBDI_SIPO         <= '1';
            processing_AD_sel  <= '1';
            
            if (last_block_input = '1') then
                enBDi_eot <= '0'; 
                no_msg <= '1';
            end if;
            
            -- absorb 2 inputs if available
            if (count_is_2 = '1') then
                bdi_ready_internal <= '0';
                reset_count <= '1';  -- reset the blk counter
                enX1        <= '1';
                enX3        <= '1';
                new_perm    <= '1';
                next_state  <= S_AD_PERM9;
        
                pad_perm   <= '0';    
                enBDI_SIPO <= '0'; 
                enBDi_eot  <= '0';

                if (bdi_pad_loc_internal = "0000" and last_block_type = '1') then
                    -- edge case of last block being full
                    pad_perm <= '1';
                end if;       
            elsif (bdi_valid='1' and bdi_type=HDR_AD) then -- check if BDI valid and type AD     
                inc_count <= '1';
            elsif (last_block_type = '1') then
                if (pad_perm_reg = '1') then
                    bdi_ready_internal <= '0'; -- do not receive PT
                end if;

                reset_count <= '1';  -- reset the blk counter
                enX1        <= '1';
                enX3        <= '1';
                new_perm    <= '1';
                pad_perm   <= '0';   
                next_state  <= S_AD_PERM9;
            elsif (bdi_valid='1' and (bdi_type=HDR_PT or bdi_type=HDR_CT)) then
                -- if not AD, then |AD|=0 so got to PT
                bdi_ready_internal <= '0';
                enBDi_eot          <= '0'; 
                enBDI_SIPO         <= '0';
                processing_AD_sel  <= '0';
                next_state         <= S_ABSORB_MSG;
            end if;
            
   ----------------------------- S_AD_PERM9 -------------------------------------------
         WHEN S_AD_PERM9 =>
            perm_is_9 <= '1';
            bdi_ready_internal <= '0';
            --enable the registers
            enX0 <= '1';
            enX1 <= '1';
            enX2 <= '1';
            enX3 <= '1';
            
            ScXorConst <= "01";
            processing_AD_sel <= '1';
                 
            if zi9 = '1' then --check if done with current 8 permutation
                ldi <= '1' ;  -- reset the permutation counter
                --disable the registers
                enX0 <= '0';
                enX1 <= '0';
                enX2 <= '0';
                enX3 <= '0';
                     
                next_state <= S_ABSORB_AD; -- go back to absorbing AD state       
                if (last_block_type = '1' and not pad_perm_reg = '1') then
                    next_state <= S_ABSORB_MSG; -- done absobing AD state   

                    if (no_msg_reg = '1') then
                        -- no msg, let pad update
                        enBDI_SIPO  <= '1'; 
                    end if;
                elsif (pad_perm_reg = '1') then
                        -- let pad update
                        enBDI_SIPO  <= '1'; 
                end if; 

            else -- keep looping inside the permutation    
                eni <= '1'; --increment i perm counter
            end if;
               
            
    ----------------------------- S_ABSORB_MSG -------------------------------------------
         WHEN S_ABSORB_MSG =>
            perm_is_9 <= '1';
            ScXorConst         <= "10"; 
            bdi_ready_internal <= '1';
            enBDI_SIPO         <= '1';
            processing_AD_sel  <= '1';
            enBDi_eot          <= '1';
            next_state <= S_ABSORB_MSG;    

            if (count_is_2 = '1') then
                -- received two inputs, process
                bdi_ready_internal <= '0';
                reset_count <= '1';  
                enX1        <= '1';
                enX3        <= '1';
                enCT_reg    <= '1';
                new_perm    <= '1';
                next_state  <= S_OUT_MSG;
                enBDI_SIPO  <= '0'; 
                enBDi_eot   <= '0';
            
                pad_perm <= '0';  

                if (bdi_pad_loc_internal = "0000" and last_block_type = '1') then
                    -- edge case of last block being full
                    pad_perm <= '1';
                end if;
                
            elsif (bdi_valid='1' and (bdi_type=HDR_PT or bdi_type=HDR_CT)) then --  
                -- received a valid input
                inc_count <= '1'; 
            
            elsif (last_block_type = '1') then
                enX1        <= '1';
                enX3        <= '1';
                next_state  <= S_OUT_MSG;
                
                -- revieved last input
                if (no_msg_reg = '1') then
                    no_msg <= '0';
                    pad_perm    <= '0';
                    enBDI_SIPO  <= '1'; 
                    enBDi_eot   <= '0';
                    new_perm    <= '1';
                    bdi_ready_internal <= '0';
                    next_state  <= S_MSG_PERM9;
                elsif (count_is_0 = '1' and pad_perm_reg = '1') then
                    -- complete post-pad permuation
                    pad_perm    <= '0';
                    enBDI_SIPO  <= '1';
                    enBDi_eot   <= '0';
                    new_perm    <= '1'; 
                    reset_count <= '1'; 
                    bdi_ready_internal <= '0';
                    next_state  <= S_MSG_PERM9;
                else
                    reset_count <= '1';  
                    enCT_reg    <= '1';
                    new_perm    <= '1';
                    next_state  <= S_OUT_MSG;
                end if;
            
            end if;
            
            if (Decrypt_in = '1' and no_msg_reg = '0' and not pad_perm_reg = '1') then
                decrypt_msg <= '1';
            end if;
            
            
    ----------------------------- S_MSG_PERM9 -------------------------------------------
       WHEN S_MSG_PERM9 =>
            perm_is_9 <= '1';
            ScXorConst <= "10";
            processing_AD_sel <= '1';
            enBDI_SIPO        <= '0';
             
             --enable the registers
             enX0 <= '1';
             enX1 <= '1';
             enX2 <= '1';
             enX3 <= '1';   
            
            if zi9 = '1' then --check if done with current 8 permutation
                ldi <= '1' ;  -- reset the permutation counter     
                enX0 <= '0';
                enX1 <= '0';
                enX2 <= '0';
                enX3 <= '0';
                
                if (last_block_type = '1'and not pad_perm_reg = '1') then
                    ScXorConst <= "00";
                    new_perm <= '1';
                    init_fin_select <= '1';
                    enX0 <= '1';
                    enX1 <= '1';
                    enX2 <= '1';
                    enX3 <= '1';
                    next_state <= S_FINAL_PERM18;
                else 
                    next_state <= S_ABSORB_MSG; -- go to the next state

                    if (pad_perm_reg = '1') then
                        -- let pad update
                        enBDI_SIPO  <= '1'; 
                    end if;
                end if;
             else -- keep looping inside the permutation 
                    
                 eni <= '1'; --increment i perm counter
                 --mux signals
                 new_perm <= '0';
                 --next_state <= current_state;
                
             end if;
           

       ----------------------------- S_OUT_MSG -------------------------------------------
       ---      the output message is of a size 64 bit while the bdo is a size 32-bit. 
       ---  Therefore, this state will output x1 left, then x3 left in the next cycle
       --- 
       WHEN S_OUT_MSG =>
            perm_is_9 <= '1';
       
            -- set the type of the output
            if decrypt_in = '1' then
                bdo_type_internal <= HDR_PT; -- output plaintext  
                decrypt_msg <= '1';
            else
                bdo_type_internal <= HDR_CT; -- output cyphertext
            end if;
            
            bdo_valid_internal <= '1';
            
            if (last_block_type = '1' and single_output = '1' and count_is_0 = '0') then
                bdo_valid_internal <= '0';    
            elsif (last_block_type = '1' and single_output = '1' and count_is_0 = '1') then
                last_output <= '1';    
            end if;   

            
            if bdo_ready = '1' or (last_block_type = '1' and single_output = '1') then
            
                if (count_is_1 = '1') then
                    if (last_block_type = '1') then
                        end_of_block_internal <= '1';       
                        last_output <= '1';                     
                    end if;

                    ldi <= '1';
                    next_state <= S_MSG_PERM9;  --go to the next state
                    reset_count <= '1';
                else
                    inc_count <= '1'; --increment the block counter

                    --next_state <= current_state;
                end if;
            
            else -- if the post processor is not ready
                --next_state <= current_state;
            end if;
            
     ----------------------------- S_FINAL_PERM18 -------------------------------------------
       WHEN S_FINAL_PERM18 =>
            perm_is_18 <= '1';
            init_fin_select <= '1';
                
            --enable all the registers
            enX0 <= '1';
            enX1 <= '1';
            enX2 <= '1';
            enX3 <= '1';
	
            if ((zi18 = '1') and count_is_1 = '1') then
                enX0 <= '0';
                enX1 <= '0';
                enX2 <= '0';
                enX3 <= '0';
            end if;
            
            if (count_is_0 = '1') then
                key_select <= '1'; --use K0
            else
                key_select <= '0'; --use K1
            end if;
            
            
            if zi18 = '1' then --check if done with current permutation
                --if zBlk1 = '1' then --check for 3rd permutation stage
                if (count_is_1 = '1') then
                    ldi <= '1'; -- reset counter i
                    reset_count <= '1';    
                    
                    if (Decrypt_in = '1') then
                        next_state <= S_Absorb_Tag;
                        rstBdi_eot <= '1';
                    else
                        next_state <= S_OUT_TAG; -- go to the next state
                        rstBdi_eot <= '1';
                    end if;
                else                    
                    new_perm <= '1';
                    ldi <= '1';            --reset counter i
                    inc_count <= '1';    --increment stage counter
                    --next_state <= current_state; 
                end if;
                
            else -- keep looping inside the permutation
            
                eni <= '1'; --increment i perm counter  
                --next_state <= current_state;                
            end if;

            
    
      ----------------------------- S_OUT_TAG -------------------------------------------
       WHEN S_OUT_TAG =>
            perm_is_18 <= '1';
            -- set the type of the output
            last_output <= '0';
            bdo_type_internal <= HDR_TAG; -- output tag  
            bdo_valid_internal <= '1';
            tag_ready_sel <= '1';
            
            if bdo_ready = '1' then
                --if ZBlk3 = '1' then
                if (count_is_3 = '1') then
                    reset_count <= '1';
                    end_of_block_internal <= '1';
                    rstBdi_eot <= '1'; -- clear values
                    next_state <= S_WAITING; -- go back to the waiting state
                else
                    inc_count <= '1'; -- increment block counter;
                    --next_state <= current_state;
                end if;
--            else
--                next_state <= current_state;
            end if;
    
    ----------------------------- S_ABSORB_TAG -------------------------------------------  
       WHEN S_ABSORB_TAG =>
            bdi_ready_internal <= '1';
            enBDI_SIPO <= '1';
            if ((bdi_valid = '1') and (bdi_type <= HDR_TAG)) then
                enTagReg <= '1';
                
                if (count_is_3 = '1') then
                    next_state <= S_Verify_TagSeg;
                    reset_count <= '1';
                else
                    inc_count <= '1';
                end if;
                
            end if;
     ----------------------------- S_Verify_TagSeg -------------------------------------------  
       WHEN S_Verify_TagSeg =>
            
            if (count_is_4 = '1') then
                -- Valid exit
                msg_auth       <= '1';
                msg_auth_valid <= '1';
                next_state     <= S_WAITING;
                rstBdi_eot     <= '1'; -- clear values
            elsif (msg_auth_ready = '1' ) then
                enTagReg <= '1';
            
                if (Tag_seg = Tag_in_seg) then
                    inc_count <= '1';
                else
                    -- Invalid exit
                    reset_count <= '1';
                    next_state <= S_WAITING;
                    rstBdi_eot <= '1'; -- clear values
                    msg_auth    <= '0';
                    msg_auth_valid <= '1';
                end if;
                
 
            end if;                                            
    END CASE;
end process State_Control; 

--output signal assignment
    key_ready    <= key_ready_internal;
    bdo_valid    <= bdo_valid_internal;
    end_of_block <= end_of_block_internal;
    bdi_ready    <= bdi_ready_internal;
    bdo_type     <= bdo_type_internal;

--////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////
------------------------------- SIPO for Key and BDI ------------------------------------------
Input_SIPO: process (clk)--, enKey_SIPO, enBDI_SIPO, bdi, key)
    begin
        if rising_edge(clk) then
        -- input  SIPO
            single_output <= single_output;

            if (rstBdi_eot = '1') then
                bdo_valid_bytes_internal       <= x"f";
            end if;

            if (enBDI_SIPO = '1' and bdi_valid = '1' and pad_perm_reg = '0' and (no_msg_reg = '0' or Decrypt_in = '0')) then
                BDI_in(r_width-1 downto r_width-CCW) <= BDI_in(r_width-CCW-1 downto 0);
                single_output <= '0';

                -- PAD Logic
                if (bdi_eot = '1') then 
                    bdo_valid_bytes_internal <= bdi_valid_bytes;
                    
                    if (count_is_1 = '1' or count_is_3 = '1') then
                        single_output <= '0';
                        if (bdi_pad_loc = "0000") then
                            BDI_in(CCW-1 downto 0) <= bdi;
                        elsif (bdi_pad_loc = "0001") then 
                            BDI_in(CCW-1 downto 0) <= bdi(31 downto 8)  & x"80";
                        elsif (bdi_pad_loc = "0010") then 
                            BDI_in(CCW-1 downto 0) <= bdi(31 downto 16) & x"8000";
                        elsif (bdi_pad_loc = "0100") then 
                            BDI_in(CCW-1 downto 0) <= bdi(31 downto 24) & x"800000";
                        elsif bdi_pad_loc = "1000" then
                            BDI_in(CCW-1 downto 0) <= x"80000000";
                        else
                            BDI_in(CCW-1 downto 0) <= bdi;
                        end if;
                    else 
                        single_output <= '1';
                        if (bdi_pad_loc = "0000") then
                            BDI_in <= bdi & x"80000000";
                        elsif (bdi_pad_loc = "0001") then 
                            BDI_in <= bdi(31 downto 8)  & x"80" & x"00000000";
                        elsif (bdi_pad_loc = "0010") then 
                            BDI_in <= bdi(31 downto 16) & x"8000" & x"00000000";
                        elsif (bdi_pad_loc = "0100") then 
                            BDI_in <= bdi(31 downto 24) & x"800000" & x"00000000";
                        elsif bdi_pad_loc = "1000" then
                            BDI_in <= x"80000000" & x"00000000";
                        else
                            BDI_in <= bdi & x"80000000";
                        end if; 
                       
                    end if;
                    
                else 
                    BDI_in(CCW-1 downto 0) <= bdi;
                end if;
                
                --enBDI_SIPO <= '0';
            elsif (enBDI_SIPO = '1') then
                if (bdi_pad_loc_internal = "1000" or bdi_pad_loc = "1000" or no_msg_reg = '1' or pad_perm_reg = '1') then
                    BDI_in <= x"8000000000000000";
                end if;       
            end if;
            
        -- Key SIPO
            if (enKey_SIPO = '1' and key_valid = '1') then
                Key_SIPO(127 downto 96) <= Key_SIPO(95 downto 64);
                Key_SIPO(95 downto 64)  <= Key_SIPO(63 downto 32);
                Key_SIPO(63 downto 32)  <= Key_SIPO(31 downto 0);
                Key_SIPO(31 downto 0)   <= Key;
                --enKey_SIPO <= '0'; 
            end if;
         
        -- Tag SIPO
             if (enTagReg = '1') then
                Tag_in(tag_size-1 downto tag_size-CCW) <= Tag_in(tag_size-CCW-1 downto tag_size-2*CCW);
                Tag_in(tag_size-CCW-1 downto tag_size-2*CCW) <= Tag_in(tag_size-2*CCW-1 downto tag_size-3*CCW);
                Tag_in(tag_size-2*CCW-1 downto tag_size-3*CCW) <= Tag_in(CCW-1 downto 0);
                Tag_in(CCW-1 downto 0) <= bdi;
                --enKey_SIPO <= '0'; 
            end if;
       
       -- CT Reg
            if (enCT_reg = '1') then
                CT_reg <=  (X1_reg_out(r_width-1 downto ccw) & X3_reg_out(r_width-1 downto ccw)) xor BDI_in;
            end if;
        end if;
        
end process Input_SIPO;
    
K0 <= Key_SIPO(key_size-1 downto r_width);
K1 <= Key_SIPO(r_width-1 downto 0);

--////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////
--------------------------------------- Counters ---------------------------------------------
-- perm step counter
counter_i: process (clk)
    begin   
        -- i counter
        if rising_edge(clk) then
            start_sb <= '0';
            
            if (new_perm = '1') then
                start_sb <= '1';
            end if;
        
            if ldi = '1' then
                i <= (others => '0');
                zi9 <= '0';
                zi18 <= '0';
            else
        
                if eni = '1' and done_sb1 = '1' then
                    start_sb <= '1';
                    i <= std_logic_vector (unsigned(i) + 1);
                    if (i = "10001") then --if i = 18
                        if perm_is_18 = '1' then
                            start_sb <= '0';
                        end if;
                            
                        zi18 <= '1';
                    elsif i = "01000" then --if i = 9
                        if perm_is_9 = '1' then
                            start_sb <= '0';
                        end if;
                    
                        zi9 <= '1';
                    end if;
                end if;    
            end if;
        end if;
        
        ---- block counter
        if rising_edge(clk) then
            if reset_count = '1' then
                count <= 0;
                count_is_0 <= '1';
                count_is_1 <= '0';
                count_is_2 <= '0';
                count_is_3 <= '0';
                count_is_4 <= '0';
            
            elsif inc_count = '1' then
                count_is_0 <= '0';
                count <= count + 1;
                if (count = 0) then 
                    count_is_1 <= '1';
                elsif (count = 1) then 
                    count_is_2 <= '1';
                    count_is_1 <= '0';
                elsif (count = 2) then 
                    count_is_3 <= '1';
                    count_is_2 <= '0';
                elsif (count = 3) then
                    count_is_4 <= '1';
                    count_is_3 <= '0';
                end if;

            end if;            
        end if;
       
    end process counter_i;
  
--////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////
--------------------------------------- Round and Step Constatnts instantiation -------------------------------------
rc_sc_ROM: entity work.dual_Rom(dataflow)
    Port MAP ( Addr_a => i,
               Addr_b => i,
               Dout_a => rc_i,
               Dout_b => sc_i);
    
    rc_0 <= rc_i(round_const_size-1 downto round_const_size/2);
    rc_1 <= rc_i(round_const_size/2 -1 downto 0);
    
    sc_0 <= sc_i(step_const_size-1 downto round_const_size/2);
    sc_1 <= sc_i(step_const_size/2 -1 downto 0);
    

--------------------------------------------------------------------------------------------------------------------
--internal signal registers register

eot_bdi_reg: process (clk)
    begin
        if rising_edge(clk) then
            if (rstBdi_eot = '1') then
                last_block_type       <= '0';
                last_block_input      <= '0';
                bdi_pad_loc_internal  <= "0000";
                bdi_msg_type_internal <= "0000";
            elsif enBdi_eot = '1' and bdi_valid = '1' then -- and bdi_ready_internal = '1'
                -- only update when enable and on completed handshake
                last_block_type      <= bdi_eot;
                last_block_input     <= bdi_eoi;
                
            end if;
            
            if bdi_valid = '1' then
                bdi_pad_loc_internal  <= bdi_pad_loc;
                bdi_msg_type_internal <= bdi_type;
            end if;
        end if;
    end process eot_bdi_reg; 
    
    
    
--------------------------------------- Permutation Process ---------------------------------------------------------
sLiSCP_perm: process (clk)

    begin       
          -- internal state registers
        if rising_edge(clk) then
            if (enX0 = '1') then
                if new_Perm = '1' THEN
                    x0_reg_out <= x0;
                elsif done_sb1 = '1' then
                    x0_reg_out <= x0perm;
                end if;
            end if;
            if (enX1 = '1') then
                if new_Perm = '1' THEN
                    x1_reg_out <= x1;
                elsif done_sb1 = '1' then
                    x1_reg_out <= x1perm;
                end if;
            end if;
            if (enX2 = '1') then
                if new_Perm = '1' THEN
                    x2_reg_out <= x2;
                elsif done_sb1 = '1' then
                    x2_reg_out <= x2perm;
                end if;
            end if;
            if (enX3 = '1') then
                if new_Perm = '1' THEN
                    x3_reg_out <= x3;
                elsif done_sb1 = '1' then
                    x3_reg_out <= x3perm;
                end if;
            end if;
        end if;
    end process sLiSCP_perm;
    
    
    SmBox_1: entity work.SB64(dataflow)
        Port MAP ( clk => clk,
                   rst => rst,
                   start => start_sb,
                   x_in => x1_reg_out,  -- input 64 bit state
                   rc   => rc_0,        -- round constant rc0
                   x_out => x0perm,
                   valid => done_sb1); -- output 64 bit state
                   
    SmBox_3: entity work.SB64(dataflow)
        Port MAP ( clk => clk,
                   rst => rst,
                   start => start_sb,
                   x_in => x3_reg_out,  -- input 64 bit state
                   rc   => rc_1,        -- round constant rc1no_msg_reg
                   x_out => x2perm,
                   valid => done_sb2); -- output 64 bit state


    x1perm <= (x2_reg_out XOR x2perm) XOR ((63 downto 8 => '1') & Sc_1);
    
    x3perm <= (x0_reg_out XOR x0perm) XOR ((63 downto 8 => '1') & Sc_0);
    
    Sr <= x1_reg_out(63 downto 32) & x3_reg_out(63 downto 32);  
    Sc <= x0_reg_out & x1_reg_out( 31 downto 0) & x2_reg_out & x3_reg_out(31 downto 0);  
    

--////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////
--------------------------------------- outside connections ------------------------------------------

----------- register mux -------------------------

x0 <= BDI_in when init = '1' else
      x0p    when init = '0';
      
x1 <= K0                     when init ='1' else
      (x1p_left & x1p_right) when init = '0';

x2 <= BDI_in when init = '1' else
      x2p    when init = '0';

x3 <= K1                     when init ='1' else
      (x3p_left & x3p_right) when init='0';
      
-- Sc Datapath
ScP <= (Sc(c_width-1 downto 2 ) & (Sc(1 downto 0) XOR ScXorConst)) when processing_AD_sel = '1' else
        Sc when processing_AD_sel = '0';

x0p        <= ScP ( c_width-1 downto c_width-r_width);
x1p_right  <= ScP (2*r_width-1 downto r_width+r_half_width);
x2p        <= ScP ( r_width+r_half_width-1 downto r_half_width);
x3p_right  <= ScP (r_half_width-1 downto 0); 
        
-- Sr Datapath
SrXorMux <= (Sr XOR K1)     when ((init_fin_select = '1') and (key_select ='1')) else
            (Sr XOR K0)     when ((init_fin_select = '1') and (key_select ='0')) else
            (Sr XOR BDI_in) when (init_fin_select = '0' and key_select ='1') else
            (Sr XOR BDI_in);

BDI_in_dec <=  BDI_in                                         when bdi_pad_loc_internal = "0000" and single_output = '0' else 
              (BDI_in(63 downto 8)  &  SrXorMux(7  downto 0)) when bdi_pad_loc_internal = "0001" and single_output = '0' else 
              (BDI_in(63 downto 16) &  SrXorMux(15 downto 0)) when bdi_pad_loc_internal = "0010" and single_output = '0' else
              (BDI_in(63 downto 24) &  SrXorMux(23 downto 0)) when bdi_pad_loc_internal = "0100" and single_output = '0' else 
              (BDI_in(63 downto 32) &  SrXorMux(31 downto 0)) when bdi_pad_loc_internal = "0000" and single_output = '1' else 
              (BDI_in(63 downto 40) &  SrXorMux(39 downto 0)) when bdi_pad_loc_internal = "0001" and single_output = '1' else 
              (BDI_in(63 downto 48) &  SrXorMux(47 downto 0)) when bdi_pad_loc_internal = "0010" and single_output = '1' else 
              (BDI_in(63 downto 56) &  SrXorMux(55 downto 0)) when bdi_pad_loc_internal = "0100" and single_output = '1' else 
               BDI_in;
              

SrP <=  BDI_in_dec when decrypt_msg = '1' else
        SrXorMux when decrypt_msg = '0';

x1p_left <= SrP (r_width-1 downto r_half_width);
x3p_left <= SrP (r_half_width-1 downto 0);

    ------- tag construction selection ---------------
Tag_seg <=  X1_reg_out(r_width-1 downto ccw) when count = 0 else
            X1_reg_out(ccw-1 downto 0)       when count = 1 else
            X3_reg_out(r_width-1 downto ccw) when count = 2 else
            X3_reg_out(ccw-1 downto 0);    --when count = 3
          
Tag_in_seg <=  Tag_in(tag_size-1 downto tag_size-CCW); 
            
----------- Output selection ---------------------------

       
bdo_valid_bytes <=  bdo_valid_bytes_internal when (last_output = '1') else x"f";
                    

BDO_reg_out <=  X3_reg_out(r_width-1 downto ccw) when (count = 1) else  --left x3 
                X1_reg_out(r_width-1 downto ccw) when (count = 0) else (others => '0'); --left x1 
                
                
BDO_out <=  CT_reg(63 downto 32) when (count = 0 and decrypt_msg = '1') else
            CT_reg(31 downto 0) when (count = 1 and decrypt_msg = '1') else
            Tag_seg when tag_ready_sel = '1' else
            BDO_reg_out when tag_ready_sel = '0';

 -- output
BDO <= BDO_out;
end mixed;