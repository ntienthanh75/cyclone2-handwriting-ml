library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Reusable sequential inference core.
-- input_pixel_index 0..195 carries one unsigned 4-bit pixel per valid cycle.
-- result_accepted='1' means a digit passed the configurable score margin.
entity ml_inference is
    generic (
        CONFIDENCE_THRESHOLD : integer := 0;
        MARGIN_THRESHOLD     : integer := 0
    );
    port (
        clk                : in  std_logic;
        reset_n            : in  std_logic;
        input_frame_valid  : in  std_logic;
        input_pixel_index  : in  unsigned(7 downto 0);
        input_pixel        : in  unsigned(3 downto 0);
        input_frame_last   : in  std_logic;
        input_frame_error  : in  std_logic;
        busy               : out std_logic;
        result_valid       : out std_logic;
        result_accepted    : out std_logic;
        result_digit       : out unsigned(3 downto 0);
        result_confidence  : out unsigned(7 downto 0);
        result_margin      : out unsigned(15 downto 0);
        result_cycles      : out unsigned(31 downto 0)
    );
end entity;

architecture rtl of ml_inference is
    component altsyncram
        generic (
            operation_mode : string := "ROM";
            width_a        : natural := 8;
            widthad_a      : natural := 13;
            numwords_a     : natural := 6272;
            outdata_reg_a  : string := "UNREGISTERED";
                     init_file      : string := "../artifacts/weights_l1.mif";
            lpm_type       : string := "altsyncram"
        );
        port (
            clock0   : in  std_logic;
            address_a: in  std_logic_vector(widthad_a-1 downto 0);
            q_a      : out std_logic_vector(width_a-1 downto 0)
        );
    end component;

    type input_array_t is array (0 to 195) of unsigned(3 downto 0);
    type hidden_array_t is array (0 to 31) of signed(63 downto 0);
    type score_array_t is array (0 to 9) of signed(63 downto 0);
    type state_t is (IDLE, LOAD, H_SETUP, H_MAC, H_NEXT,
                     O_SETUP, O_MAC, FINISH, REJECT_FRAME);

    signal input_mem : input_array_t := (others => (others => '0'));
    signal hidden    : hidden_array_t := (others => (others => '0'));
    signal scores    : score_array_t := (others => (others => '0'));
    signal state     : state_t := IDLE;
    signal pixel_idx : integer range 0 to 195 := 0;
    signal neuron    : integer range 0 to 31 := 0;
    signal output_n  : integer range 0 to 9 := 0;
    signal acc       : signed(63 downto 0) := (others => '0');
    signal cycle_ctr : unsigned(31 downto 0) := (others => '0');
    signal best_score, second_score : signed(63 downto 0) := (others => '0');
    signal best_digit : unsigned(3 downto 0) := (others => '0');

    signal l1_addr : std_logic_vector(12 downto 0) := (others => '0');
    signal l1_data : std_logic_vector(7 downto 0);
    signal l2_addr : std_logic_vector(8 downto 0) := (others => '0');
    signal l2_data : std_logic_vector(7 downto 0);
    signal b1_addr : std_logic_vector(5 downto 0) := (others => '0');
    signal b1_data : std_logic_vector(31 downto 0);
    signal b2_addr : std_logic_vector(3 downto 0) := (others => '0');
    signal b2_data : std_logic_vector(31 downto 0);

    function sat8(v : signed(63 downto 0)) return unsigned is
        variable n : integer;
    begin
        n := to_integer(v(31 downto 0));
        if n < 0 then return to_unsigned(0, 8); end if;
        if n > 255 then return to_unsigned(255, 8); end if;
        return to_unsigned(n, 8);
    end function;

    function sat16(v : signed(63 downto 0)) return unsigned is
        variable n : integer;
    begin
        n := to_integer(v(31 downto 0));
        if n < 0 then return to_unsigned(0, 16); end if;
        if n > 65535 then return to_unsigned(65535, 16); end if;
        return to_unsigned(n, 16);
    end function;
begin
    l1_rom : altsyncram
        generic map (width_a => 8, widthad_a => 13, numwords_a => 6272,
                     init_file => "../artifacts/weights_l1.mif")
        port map (clock0 => clk, address_a => l1_addr, q_a => l1_data);
    l2_rom : altsyncram
        generic map (width_a => 8, widthad_a => 9, numwords_a => 320,
                     init_file => "../artifacts/weights_l2.mif")
        port map (clock0 => clk, address_a => l2_addr, q_a => l2_data);
    b1_rom : altsyncram
        generic map (width_a => 32, widthad_a => 6, numwords_a => 32,
                     init_file => "../artifacts/bias_l1.mif")
        port map (clock0 => clk, address_a => b1_addr, q_a => b1_data);
    b2_rom : altsyncram
        generic map (width_a => 32, widthad_a => 4, numwords_a => 10,
                     init_file => "../artifacts/bias_l2.mif")
        port map (clock0 => clk, address_a => b2_addr, q_a => b2_data);

    busy <= '1' when state /= IDLE and state /= FINISH and state /= REJECT_FRAME else '0';

    process(clk)
        variable product : signed(63 downto 0);
        variable next_acc : signed(63 downto 0);
        variable margin_v : signed(63 downto 0);
        variable scan_best : signed(63 downto 0);
        variable scan_second : signed(63 downto 0);
        variable scan_digit : unsigned(3 downto 0);
    begin
        if rising_edge(clk) then
            result_valid <= '0';
            if reset_n = '0' then
                state <= IDLE;
                cycle_ctr <= (others => '0');
                result_accepted <= '0';
                result_digit <= (others => '0');
                result_confidence <= (others => '0');
                result_margin <= (others => '0');
                result_cycles <= (others => '0');
            else
                if state /= IDLE then cycle_ctr <= cycle_ctr + 1; end if;
                case state is
                    when IDLE =>
                        if input_frame_error = '1' then
                            state <= REJECT_FRAME;
                        elsif input_frame_valid = '1' then
                            input_mem(to_integer(input_pixel_index)) <= input_pixel;
                            if input_frame_last = '1' or input_pixel_index = 195 then
                                neuron <= 0; pixel_idx <= 0; state <= H_SETUP;
                            else
                                state <= LOAD;
                            end if;
                        end if;
                    when LOAD =>
                        if input_frame_valid = '1' then
                            input_mem(to_integer(input_pixel_index)) <= input_pixel;
                            if input_frame_last = '1' or input_pixel_index = 195 then
                                neuron <= 0; pixel_idx <= 0; state <= H_SETUP;
                            end if;
                        end if;
                    when H_SETUP =>
                        l1_addr <= std_logic_vector(to_unsigned(neuron * 196 + pixel_idx, 13));
                        b1_addr <= std_logic_vector(to_unsigned(neuron, 6));
                        -- The ROM address is presented in this cycle.  The
                        -- following H_MAC cycle consumes the settled data.
                        acc <= (others => '0');
                        state <= H_MAC;
                    when H_MAC =>
                        product := resize(signed(resize(input_mem(pixel_idx), 8)) * signed(l1_data), 64);
                        if pixel_idx = 0 then
                            next_acc := resize(signed(b1_data), 64) + product;
                        else
                            next_acc := acc + product;
                        end if;
                        if pixel_idx = 195 then
                            if next_acc < 0 then hidden(neuron) <= (others => '0');
                            else hidden(neuron) <= next_acc; end if;
                            state <= H_NEXT;
                        else
                            acc <= next_acc; pixel_idx <= pixel_idx + 1; state <= H_SETUP;
                        end if;
                    when H_NEXT =>
                        if neuron = 31 then output_n <= 0; neuron <= 0; state <= O_SETUP;
                        else neuron <= neuron + 1; pixel_idx <= 0; state <= H_SETUP; end if;
                    when O_SETUP =>
                        l2_addr <= std_logic_vector(to_unsigned(output_n * 32 + neuron, 9));
                        b2_addr <= std_logic_vector(to_unsigned(output_n, 4));
                        -- As above, consume the addressed ROM data in the
                        -- next O_MAC cycle.  neuron is preserved here so the
                        -- 32 hidden activations are visited in order.
                        acc <= (others => '0'); state <= O_MAC;
                    when O_MAC =>
                        product := resize(hidden(neuron) * signed(l2_data), 64);
                        if neuron = 0 then
                            next_acc := resize(signed(b2_data), 64) + product;
                        else
                            next_acc := acc + product;
                        end if;
                        if neuron = 31 then
                            scores(output_n) <= next_acc;
                            if output_n = 9 then state <= FINISH;
                            else output_n <= output_n + 1; state <= O_SETUP; end if;
                        else
                            acc <= next_acc; neuron <= neuron + 1; state <= O_SETUP;
                        end if;
                    when FINISH =>
                        scan_best := scores(0); scan_second := scores(1); scan_digit := (others => '0');
                        for i in 1 to 9 loop
                            if scores(i) > scan_best then
                                scan_second := scan_best; scan_best := scores(i); scan_digit := to_unsigned(i, 4);
                            elsif scores(i) > scan_second then scan_second := scores(i); end if;
                        end loop;
                        margin_v := scan_best - scan_second;
                        best_score <= scan_best; second_score <= scan_second; best_digit <= scan_digit;
                        result_digit <= scan_digit;
                        result_confidence <= sat8(scan_best);
                        result_margin <= sat16(margin_v);
                        if scan_best >= CONFIDENCE_THRESHOLD and margin_v >= MARGIN_THRESHOLD then
                            result_accepted <= '1';
                        else
                            result_accepted <= '0';
                        end if;
                        result_cycles <= cycle_ctr;
                        result_valid <= '1'; state <= IDLE;
                    when REJECT_FRAME =>
                        result_accepted <= '0'; result_digit <= (others => '0');
                        result_confidence <= (others => '0'); result_margin <= (others => '0');
                        result_cycles <= cycle_ctr; result_valid <= '1'; state <= IDLE;
                end case;
            end if;
        end if;
    end process;
end architecture;
