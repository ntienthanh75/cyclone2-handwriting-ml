library verilog;
use verilog.vl_types.all;
entity ml_inference is
    generic(
        CONFIDENCE_THRESHOLD: integer := 0;
        MARGIN_THRESHOLD: integer := 0
    );
    port(
        clk             : in     vl_logic;
        reset_n         : in     vl_logic;
        input_frame_valid: in     vl_logic;
        input_pixel_index: in     vl_logic_vector(7 downto 0);
        input_pixel     : in     vl_logic_vector(3 downto 0);
        input_frame_last: in     vl_logic;
        input_frame_error: in     vl_logic;
        busy            : out    vl_logic;
        result_valid    : out    vl_logic;
        result_accepted : out    vl_logic;
        result_digit    : out    vl_logic_vector(3 downto 0);
        result_confidence: out    vl_logic_vector(7 downto 0);
        result_margin   : out    vl_logic_vector(15 downto 0);
        result_cycles   : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CONFIDENCE_THRESHOLD : constant is 2;
    attribute mti_svvh_generic_type of MARGIN_THRESHOLD : constant is 2;
end ml_inference;
