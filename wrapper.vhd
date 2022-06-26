library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;


entity wrapper is
    port (
        clk_i       :   in  std_logic;
        rst_i       :   in  std_logic;
        cpu_addr_i  :   in  std_logic_vector(31 downto 0);
        cpu_data_o  :   out std_logic_vector(31 downto 0);
        cpu_data_i  :   in  std_logic_vector(31 downto 0);
        cpu_data_w_i:   in  std_logic_vector(3 downto 0)
    );  
end wrapper;

architecture wrapper of wrapper  is
    signal ext_miniaes : std_logic := '0';

    function to_string ( a: std_logic_vector) return string is -- ref: https://stackoverflow.com/a/38850022
        variable b : string (1 to a'length) := (others => NUL);
        variable stri : integer := 1; 
        begin
            for i in a'range loop
                b(stri) := std_logic'image(a((i)))(2);
                stri := stri+1;
            end loop;
        return b;
    end function;

begin

    ext_miniaes <= '1' when cpu_addr_i(31 downto 23) = x"e6" else '0';

    process(clk_i, rst_i)
    begin
        if clk_i'event and clk_i = '1' then
            if ext_miniaes = '1' then
                report(to_string(cpu_addr_i));
            end if;
        end if;
    end process;

end wrapper;