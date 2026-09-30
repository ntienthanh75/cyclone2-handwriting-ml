package ml_inference_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class ml_frame extends uvm_sequence_item;
    rand bit [3:0] pixels[196]; bit frame_error;
    `uvm_object_utils(ml_frame)
    function new(string name="ml_frame"); super.new(name); endfunction
  endclass

  class ml_frame_seq extends uvm_sequence #(ml_frame);
    `uvm_object_utils(ml_frame_seq)
    function new(string name="ml_frame_seq"); super.new(name); endfunction
    task body();
      ml_frame tr = ml_frame::type_id::create("tr"); start_item(tr);
      foreach (tr.pixels[i]) tr.pixels[i] = 0; tr.frame_error = 0; finish_item(tr);
    endtask
  endclass

  class ml_golden_seq extends uvm_sequence #(ml_frame);
    `uvm_object_utils(ml_golden_seq)
    function new(string name="ml_golden_seq"); super.new(name); endfunction
    task body();
      ml_frame tr;
      for (int pattern=0; pattern<4; pattern++) begin
        tr = ml_frame::type_id::create($sformatf("golden_%0d", pattern));
        start_item(tr);
        for (int i=0; i<196; i++) begin
          case (pattern)
            0: tr.pixels[i] = 0;
            1: tr.pixels[i] = 15;
            2: tr.pixels[i] = (i % 2 == 0) ? 15 : 0;
            default: tr.pixels[i] = ((i / 14) == (i % 14)) ? 15 : 0;
          endcase
        end
        tr.frame_error = 0;
        finish_item(tr);
      end
    endtask
  endclass

  class ml_driver extends uvm_driver #(ml_frame);
    `uvm_component_utils(ml_driver)
    virtual ml_inference_if vif;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual ml_inference_if)::get(this,"","vif",vif)) `uvm_fatal("NOVIF","driver vif missing")
    endfunction
    task run_phase(uvm_phase phase);
      ml_frame tr; vif.input_frame_valid<=0; vif.input_frame_last<=0; vif.input_frame_error<=0;
      forever begin
        seq_item_port.get_next_item(tr);
        while (vif.busy) @(negedge vif.clk);
        for (int i=0;i<196;i++) begin @(negedge vif.clk);
          vif.input_frame_valid<=1; vif.input_pixel_index<=i; vif.input_pixel<=tr.pixels[i];
          vif.input_frame_last<=(i==195); vif.input_frame_error<=tr.frame_error;
        end
        @(negedge vif.clk); vif.input_frame_valid<=0; vif.input_frame_last<=0; vif.input_frame_error<=0;
        while (vif.busy) @(negedge vif.clk);
        seq_item_port.item_done();
      end
    endtask
  endclass

  class ml_result extends uvm_sequence_item;
    bit accepted; bit [3:0] digit; bit [7:0] confidence; bit [15:0] margin; bit [31:0] cycles;
    `uvm_object_utils(ml_result)
    function new(string name="ml_result"); super.new(name); endfunction
  endclass

  class ml_monitor extends uvm_monitor;
    `uvm_component_utils(ml_monitor)
    virtual ml_inference_if vif; uvm_analysis_port #(ml_result) ap;
    function new(string name, uvm_component parent); super.new(name,parent); ap=new("ap",this); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual ml_inference_if)::get(this,"","vif",vif)) `uvm_fatal("NOVIF","monitor vif missing")
    endfunction
    task run_phase(uvm_phase phase);
      forever begin @(posedge vif.clk); if (vif.result_valid) begin
        ml_result r=ml_result::type_id::create("r"); r.accepted=vif.result_accepted; r.digit=vif.result_digit;
        r.confidence=vif.result_confidence; r.margin=vif.result_margin; r.cycles=vif.result_cycles; ap.write(r);
      end end
    endtask
  endclass

  class ml_scoreboard extends uvm_subscriber #(ml_result);
    `uvm_component_utils(ml_scoreboard) int results_seen;
    bit golden_mode; bit [3:0] expected_digit[4]; bit [7:0] expected_confidence[4]; bit [15:0] expected_margin[4];
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void write(ml_result t);
      results_seen++;
      if (t.cycles==0) `uvm_error("BAD_RESULT","result cycle count is zero")
      else `uvm_info("RESULT",$sformatf("digit=%0d accepted=%0d confidence=%0d margin=%0d cycles=%0d",t.digit,t.accepted,t.confidence,t.margin,t.cycles),UVM_LOW);
      if (golden_mode && results_seen <= 4) begin
        if (t.digit !== expected_digit[results_seen-1]) `uvm_error("GOLDEN_DIGIT",$sformatf("vector %0d expected digit %0d got %0d",results_seen-1,expected_digit[results_seen-1],t.digit))
        if (t.confidence !== expected_confidence[results_seen-1]) `uvm_error("GOLDEN_CONFIDENCE",$sformatf("vector %0d expected confidence %0d got %0d",results_seen-1,expected_confidence[results_seen-1],t.confidence))
        if (t.margin !== expected_margin[results_seen-1]) `uvm_error("GOLDEN_MARGIN",$sformatf("vector %0d expected margin %0d got %0d",results_seen-1,expected_margin[results_seen-1],t.margin))
      end
    endfunction
  endclass

  class ml_env extends uvm_env;
    `uvm_component_utils(ml_env)
    uvm_sequencer #(ml_frame) sequencer; ml_driver driver; ml_monitor monitor; ml_scoreboard scoreboard;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase); sequencer=uvm_sequencer#(ml_frame)::type_id::create("sequencer",this);
      driver=ml_driver::type_id::create("driver",this); monitor=ml_monitor::type_id::create("monitor",this); scoreboard=ml_scoreboard::type_id::create("scoreboard",this);
    endfunction
    function void connect_phase(uvm_phase phase); driver.seq_item_port.connect(sequencer.seq_item_export); monitor.ap.connect(scoreboard.analysis_export); endfunction
  endclass

  class ml_smoke_test extends uvm_test;
    `uvm_component_utils(ml_smoke_test)
    ml_env env; virtual ml_inference_if vif;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase); env=ml_env::type_id::create("env",this);
      if (!uvm_config_db#(virtual ml_inference_if)::get(this,"","vif",vif)) `uvm_fatal("NOVIF","test vif missing")
    endfunction
    task run_phase(uvm_phase phase);
      ml_frame_seq seq=ml_frame_seq::type_id::create("seq"); phase.raise_objection(this); seq.start(env.sequencer);
      repeat (250000) begin @(posedge vif.clk); if (env.scoreboard.results_seen>0) break; end
      if (env.scoreboard.results_seen==0) `uvm_error("TIMEOUT","DUT did not produce result_valid")
      phase.drop_objection(this);
    endtask
  endclass

  class ml_golden_test extends uvm_test;
    `uvm_component_utils(ml_golden_test)
    ml_env env; virtual ml_inference_if vif;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase); env=ml_env::type_id::create("env",this);
      if (!uvm_config_db#(virtual ml_inference_if)::get(this,"","vif",vif)) `uvm_fatal("NOVIF","test vif missing")
    endfunction
    function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      env.scoreboard.golden_mode = 1;
      env.scoreboard.expected_digit = '{2,2,5,2};
      env.scoreboard.expected_confidence = '{255,255,255,255};
      env.scoreboard.expected_margin = '{4543,65535,65535,8587};
    endfunction
    task run_phase(uvm_phase phase);
      ml_golden_seq seq=ml_golden_seq::type_id::create("seq");
      phase.raise_objection(this); wait (vif.reset_n === 1'b1); seq.start(env.sequencer);
      repeat (1200000) begin @(posedge vif.clk); if (env.scoreboard.results_seen>=4) break; end
      if (env.scoreboard.results_seen<4) `uvm_error("TIMEOUT",$sformatf("only %0d of 4 golden results arrived",env.scoreboard.results_seen))
      phase.drop_objection(this);
    endtask
  endclass
endpackage
