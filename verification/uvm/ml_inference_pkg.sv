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
        for (int i=0;i<196;i++) begin @(negedge vif.clk);
          vif.input_frame_valid<=1; vif.input_pixel_index<=i; vif.input_pixel<=tr.pixels[i];
          vif.input_frame_last<=(i==195); vif.input_frame_error<=tr.frame_error;
        end
        @(negedge vif.clk); vif.input_frame_valid<=0; vif.input_frame_last<=0; vif.input_frame_error<=0;
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
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void write(ml_result t);
      results_seen++;
      if (t.cycles==0) `uvm_error("BAD_RESULT","result cycle count is zero")
      else `uvm_info("RESULT",$sformatf("digit=%0d accepted=%0d confidence=%0d margin=%0d cycles=%0d",t.digit,t.accepted,t.confidence,t.margin,t.cycles),UVM_LOW);
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
endpackage
