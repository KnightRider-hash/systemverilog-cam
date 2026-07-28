class CamTransaction;
    // The data we want to send to the CAM
    rand logic        wr;      
    rand logic [1:0]  wr_adr;   
    rand logic [31:0] din;      
    rand logic [31:0] sword;   
    logic        emp; 
    logic [1:0]  adr; 

    constraint magic_test_values {
        
        sword dist {
            32'h1122_3344 := 1, 
            32'hDEAD_BEEF := 1, 
            32'hCAFE_BABE := 1, 
            32'h8877_6655 := 1,
            // Pick a completely random 32-bit number 20% of the time
            [32'h0000_0000 : 32'hFFFF_FFFF] :/ 1 
        };


        din dist{
            32'h1122_3344 := 1, 
            32'hDEAD_BEEF := 1, 
            32'hCAFE_BABE := 1, 
            32'h8877_6655 := 1,
            // Pick a completely random 32-bit number 20% of the time
            [32'h0000_0000 : 32'hFFFF_FFFF] :/ 1 
        };
    }
endclass




class CamGenerator;
    mailbox gen_to_drv; // builtin memory buffer named gen_to_drv

    // Create an array holding the 4 specific 32-bit data values you want to test
    logic [31:0] magic_data [4] = '{
        32'h1122_3344,
        32'hDEAD_BEEF,
        32'hCAFE_BABE,
        32'h8877_6655
    };

    task run(); // task is like void
        CamTransaction tx;

    
        $display("Starting Phase 1: Writing known data..."); //phase 1
        for (int i = 0; i < 4; i++) begin
            tx = new();
            // Force the transaction to write data[i] into address[i]
            tx.randomize() with { 
                wr     == 1'b1;          
                wr_adr == i;             
                din    == magic_data[i]; 
            };
            gen_to_drv.put(tx);
        end

       
        $display("Starting Phase 2: Searching known data..."); // phase 2 :searching 
        for (int i = 0; i < 4; i++) begin
            tx = new();
            // Force the transaction to search for the data we just wrote
            tx.randomize() with { 
                wr    == 1'b0;           // Force Search Mode
                sword == magic_data[i];  // Search for the data from our array
            };
            gen_to_drv.put(tx);
        end

     
        $display("Starting Phase 3: Random testing..."); // pahse 3: random
        for (int i = 0; i < 20; i++) begin
            tx = new();
            // Let the dice roll naturally with no overrides!
            if (!tx.randomize()) $error("Randomization failed!");
            
            gen_to_drv.put(tx);
        end
        
    endtask
endclass



class CamDriver;
   
    virtual cambus v_bus; // for bridging software with hardware , cambus due to interface name

    // 2. The Conveyor Belt
    mailbox gen_to_drv;

    // 3. The Main Job
    task run();
        CamTransaction tx; // Create an empty nametag for the envelope

        
        forever begin // A Driver runs forever
            
          
            gen_to_drv.get(tx); // waits for new data
         
            @(posedge v_bus.clk);
            
          
            v_bus.wr     <= tx.wr;
            v_bus.wr_adr <= tx.wr_adr;
            v_bus.din    <= tx.din;
            v_bus.sword  <= tx.sword;
            
        end
    endtask
endclass



class CamMonitor;
   
    virtual cambus v_bus; /* reads i/o of module which under test ,
     can be named differently than used in driver as the are not linked the connection is made in top*/

   
    mailbox mon_to_sb; // buffer for montior to scoreboard

    task run();
        CamTransaction tx;
        
        forever begin
            // 1. Wait for the clock edge
            @(posedge v_bus.clk);
            
            // 2. Wait just 1 nanosecond for the hardware flip-flops to update
            // (Since DUT uses <=, outputs change a fraction of time after the clock)
            #1; 
            
            // 3. Create a fresh envelope to hold the evidence
            tx = new();
            
            // 4. Copy the physical pins into the software envelope
            tx.wr     = v_bus.wr;
            tx.wr_adr = v_bus.wr_adr;
            tx.din    = v_bus.din;
            tx.sword  = v_bus.sword;
            tx.emp    = v_bus.emp; // The hardware output!
            tx.adr    = v_bus.adr; // The hardware output!
            
            // 5. Send the evidence to the Judge
            mon_to_sb.put(tx);
        end
    endtask
endclass



class CamScoreboard;
    
    mailbox mon_to_sb; // just a pointer actual thing in the env
    
    // THE GOLDEN MODEL: A perfect software replica of your 4-slot CAM
    logic [31:0] perfect_cam [4];

    task run();
        CamTransaction tx; //Create an empty variable
        logic expected_emp; // What we think the answer should be
        
        forever begin
            
            mon_to_sb.get(tx); // The mailbox spits out an Envelope and lands it on 'tx'

            if (tx.wr == 1'b1) begin // its a write operation & therefore its part
               
                perfect_cam[tx.wr_adr] = tx.din; 
                $display("[SCOREBOARD] Wrote %h to address %0d", tx.din, tx.wr_adr);
                
            end else begin // else its a search operation
                
                expected_emp = 1'b1; // Assume it's empty (not found) by default
                
                for (int i = 0; i < 4; i++) begin
                    if (perfect_cam[i] == tx.sword) begin
                        expected_emp = 1'b0; // Found it! So 'empty' should be 0
                    end
                end
                
                // Now, compare our software answer against the physical hardware answer!
                if (tx.emp !== expected_emp) begin
                    $error("[FAIL] Searched for %h. Hardware emp=%0b, but expected emp=%0b", 
                           tx.sword, tx.emp, expected_emp);
                end else begin
                    $display("[PASS] Searched for %h. Hardware emp matched perfectly.", tx.sword);
                end
            end
        end
    endtask
endclass







class CamEnvironment;
    //  Declare the Workers
    CamGenerator  gen;
    CamDriver     drv;
    CamMonitor    mon;
    CamScoreboard sb;

    
    mailbox m_gen_to_drv; // actual buffer is created gen to driver
    mailbox m_mon_to_sb;  // for monitor to scoreboard

    // The 'new' function runs the instant the Environment is created
    function new(virtual cambus v_bus);
        
        // ACTION 1: Build the physical mailboxes in RAM
        m_gen_to_drv = new();
        m_mon_to_sb  = new();

        // ACTION 2: Hire the workers (Create them in RAM)
        gen = new();
        drv = new();
        mon = new();
        sb  = new();

        // ACTION 3: Connect the Generator and Driver together!
        // We give both workers a pointer to the EXACT SAME mailbox
        gen.gen_to_drv = m_gen_to_drv;
        drv.gen_to_drv = m_gen_to_drv;

        // ACTION 4: Connect the Monitor and Scoreboard together!
        // The Monitor gets one end of the tube, the Scoreboard gets the other.
        mon.mon_to_sb = m_mon_to_sb;
        sb.mon_to_sb  = m_mon_to_sb;

        // ACTION 5: Connect the hardware cameras!
        // Give the Driver and Monitor the exact same physical interface pointer
        drv.v_bus = v_bus;
        mon.v_bus = v_bus;
        
    endfunction

    // The task that tells all four workers to start doing their jobs simultaneously
    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
            sb.run();
        join_none
    endtask

endclass


class CamTest;
    // 1. The CEO owns the Manager
    CamEnvironment env;

    // 2. Build the Manager and pass it the hardware pointer
    function new(virtual cambus v_bus);
        env = new(v_bus);
    endfunction

    // 3. Tell the Manager to start working
    task run();
        $display("Starting the CAM Test...");
        env.run(); 
    endtask
endclass



module top_tb;
    // 1. Physical time and reset
    logic clk;
    logic rst;

    // 2. The physical copper cables
    cambus bus(); 
    
    assign bus.clk = clk;
    assign bus.rst = rst;

    // 3. The Physical Hardware (Device Under Test)
    cam DUT (
        .clk(bus.clk),
        .rst(bus.rst),
        .wr(bus.wr),
        .wr_adr(bus.wr_adr),
        .din(bus.din),
        .sword(bus.sword),
        .emp(bus.emp),
        .adr(bus.adr)
    );

    // 4. The Clock Generator (Runs forever in the background)
    always #5 clk = ~clk;

    // 5. The Software CEO
    CamTest test;

    // 6. The Master Power Switch
    initial begin

        $dumpfile("dump.vcd"); // Create the file
        $dumpvars(0, top_tb);  // Record everything in top_tb and below
        clk = 0;
        rst = 1;
       //#50rst = 0; // Release reset after 15 nanoseconds

        // Hire the CEO and hand him the physical cables
        test = new(bus);

        // Turn on the software!
        test.run();

        // End the simulation after giving the software enough time to finish
        #100000;
        $finish;
    end
endmodule




