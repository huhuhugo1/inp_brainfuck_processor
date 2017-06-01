-- cpu.vhd: Simple 8-bit CPU (BrainLove interpreter)
-- Copyright (C) 2016 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Juraj Kubis
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (1) / zapis (0)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
 -- zde dopiste potrebne deklarace signalu
   signal pc_out           : std_logic_vector(11 downto 0) := (others => '0');
   signal pc_inc, pc_dec   : std_logic;

   signal cnt_out          : std_logic_vector(7 downto 0) := (others => '0');
   signal cnt_inc, cnt_dec : std_logic;

   signal cnt_cmp          : std_logic;

   signal tmp_out          : std_logic_vector(7 downto 0) := (others => '0');
   signal tmp_ld           : std_logic;

   signal ptr_out          : std_logic_vector(9 downto 0) := (others => '0');
   signal ptr_inc, ptr_dec : std_logic;

   signal data_cmp         : std_logic;

   signal sel              : std_logic_vector(1 downto 0);

   type state_type is (s_FETCH,s_DECODE,s_INCM_2,s_DECM_2,s_JMPZ_2,s_JMPZ_3,s_JMPZ_4,s_JPNZ_2,s_JPNZ_3,s_JPNZ_4,s_JPNZ_5, s_PUTC_2);
   signal present_state, next_state   : state_type;

begin
   OUT_DATA <= DATA_RDATA;

   PC: process(CLK, RESET)
   begin
      if RESET = '1' then
         pc_out <= (others => '0');
      elsif (CLK'event and CLK = '1') then 
         if (pc_inc = '1') then
            pc_out <= pc_out + 1;
         end if;
         if (pc_dec = '1') then 
            pc_out <= pc_out - 1;
         end if;
      end if;   
   end process PC;

   CODE_ADDR <= pc_out;

   CNT: process(CLK, RESET)
   begin
      if RESET = '1' then
         cnt_out <= (others => '0');
      elsif (CLK'event and CLK = '1') then 
         if (cnt_inc = '1') then
            cnt_out <= cnt_out + 1;
         end if;
         if (cnt_dec = '1') then 
            cnt_out <= cnt_out - 1;
         end if;
      end if;   
   end process CNT;

   CNT_COMPARATOR: process(cnt_out)
   begin
      if (cnt_out = "00000000") then
         cnt_cmp <= '1';
      else
         cnt_cmp <= '0';
      end if;
   end process CNT_COMPARATOR;

   TMP: process(CLK, RESET)
   begin
      if RESET = '1' then
         tmp_out <= (others => '0');
      elsif (CLK'event and CLK = '1') then 
         if (tmp_ld = '1') then
            tmp_out <= DATA_RDATA;
         end if;
      end if;   
   end process TMP;

   PTR: process(CLK, RESET)
   begin
      if RESET = '1' then
         ptr_out <= (others => '0');
      elsif (CLK'event and CLK = '1') then 
         if (ptr_inc = '1') then
            ptr_out <= ptr_out + 1;
         end if;
         if (ptr_dec = '1') then 
            ptr_out <= ptr_out - 1;
         end if;
      end if;   
   end process PTR;

   DATA_ADDR <= ptr_out;

   DATA_COMPARATOR: process(DATA_RDATA)
   begin
      if (DATA_RDATA = "00000000") then
         data_cmp <= '1';
      else
         data_cmp <= '0';
      end if;
   end process DATA_COMPARATOR;

   MX: process(sel, IN_DATA, tmp_out, DATA_RDATA)
   begin
      case sel is
         when "00" => DATA_WDATA <= IN_DATA;
         when "01" => DATA_WDATA <= tmp_out;
         when "10" => DATA_WDATA <= DATA_RDATA - 1;
         when others => DATA_WDATA <= DATA_RDATA + 1;
      end case;
   end process MX;

   FSM_SYNC: process(CLK, RESET)
   begin
      if (RESET = '1') then
         present_state <= s_FETCH;
      elsif (CLK'event and CLK = '1') then
         if (EN = '1') then
            present_state <= next_state;
         end if; 
      end if;
   end process FSM_SYNC;

   FSM_NSL: process(present_state, CODE_DATA, data_cmp, cnt_cmp, OUT_BUSY, IN_VLD)
   begin
      CODE_EN <= '0';
      
      IN_REQ <= '0';
      OUT_WE <= '0';

      pc_inc <= '0';
      pc_dec <= '0';

      cnt_inc <= '0';
      cnt_dec <= '0';

      tmp_ld <= '0';

      ptr_inc <= '0';
      ptr_dec <= '0';

      sel <= "00";

      DATA_EN <= '0';
      DATA_RDWR <= '1';

      case present_state is

         when s_FETCH =>
            next_state <= s_DECODE;
            CODE_EN <= '1';

         when s_DECODE =>
            case CODE_DATA is
               when x"00"  => 
                  next_state <= s_FETCH;
               
               when x"21"  => 
                  next_state <= s_FETCH;
                  DATA_EN <= '1';
                  DATA_RDWR <= '0';
                  sel <= "01";
                  pc_inc <= '1';
               
               when x"24"  =>
                  next_state <= s_FETCH;
                  DATA_EN <= '1';
                  DATA_RDWR <= '1';
                  tmp_ld <= '1';
                  pc_inc <= '1';
               
               when x"2C"  => 
                  IN_REQ <= '1';
                  if (IN_VLD = '1') then
                     next_state <= s_FETCH;
                     DATA_EN <= '1';
                     DATA_RDWR <= '0';
                     sel <= "00";
                     pc_inc <= '1'; 
                  else
                     next_state <= s_DECODE;
                  end if;
               
               when x"2E"  => 
                  DATA_EN <= '1';
                  DATA_RDWR <= '1';
                  next_state <= s_PUTC_2;
               
               when x"5D"  => 
                  next_state <= s_JPNZ_2;
                  DATA_EN <= '1';
                  DATA_RDWR <= '1';
               
               when x"5B"  => 
                  next_state <= s_JMPZ_2;
                  pc_inc <= '1';
                  DATA_EN <= '1';
                  DATA_RDWR <= '1';
               
               when x"2D"  => 
                  next_state <= s_DECM_2;
                  DATA_EN <= '1';
                  DATA_RDWR <= '1';
               
               when x"2B"  => 
                  next_state <= s_INCM_2;
                  DATA_EN <= '1';
                  DATA_RDWR <= '1';
               
               when x"3C"  => 
                  next_state <= s_FETCH;
                  ptr_dec <= '1';
                  pc_inc <= '1';
               
               when x"3E"  => 
                  next_state <= s_FETCH;
                  ptr_inc <= '1';
                  pc_inc <= '1';
               
               when others => 
                  next_state <= s_FETCH;            
                  pc_inc <= '1';
            end case;
            
         when s_INCM_2 =>
            next_state <= s_FETCH;
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            sel <= "11";
            pc_inc <= '1';

         when s_DECM_2 =>
            next_state <= s_FETCH;
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            sel <= "10";
            pc_inc <= '1';

         when s_JMPZ_2 =>
            if (data_cmp = '1') then 
               next_state <= s_JMPZ_3;
               cnt_inc <= '1';
            else
               next_state <= s_FETCH;
            end if;

         when s_JMPZ_3 =>
            if (cnt_cmp = '0') then
               next_state <= s_JMPZ_4;
               CODE_EN <= '1';
            else
                next_state <= s_FETCH; 
            end if;

         when s_JMPZ_4 =>
            next_state <= s_JMPZ_3;
            if (CODE_DATA = x"5B") then 
               cnt_inc <= '1';
            elsif (CODE_DATA = x"5D") then 
               cnt_dec <= '1';
            end if;
            pc_inc <= '1';

         when s_JPNZ_2 =>
            if (data_cmp = '1') then 
               pc_inc <= '1';
               next_state <= s_FETCH;
            else
               cnt_inc <= '1';
               pc_dec <= '1';
               next_state <= s_JPNZ_3;
            end if;

         when s_JPNZ_3 =>
            if (cnt_cmp = '0') then 
               next_state <= s_JPNZ_4;
               CODE_EN <= '1';
            else
               next_state <= s_FETCH;
            end if;

         when s_JPNZ_4 => 
            if (CODE_DATA = x"5D") then 
               cnt_inc <= '1';
            elsif (CODE_DATA = x"5B") then 
               cnt_dec <= '1';
            end if;
            next_state <= s_JPNZ_5;

         when s_JPNZ_5 => 
            if (cnt_cmp = '1') then 
               pc_inc <= '1';
            else
               pc_dec <= '1';
            end if;
            next_state <= s_JPNZ_3;

         when s_PUTC_2 =>
            if (OUT_BUSY = '0') then
               next_state <= s_FETCH;
               OUT_WE <= '1';
               pc_inc <= '1';
            else
               next_state <= s_PUTC_2;
            end if;
      end case;
   end process FSM_NSL;
end behavioral;
 
