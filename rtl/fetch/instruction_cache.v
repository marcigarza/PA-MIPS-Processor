// Instruction Cache does not allow write requests from the fetch logic, only
// reads are allowed. The Instruction cache implementation must
// ensure that one request can be served each cycle if there are no misses.
// Otheriwse, in case of a miss it takes `MAIN_MEMORY_LATENCY cycles to go to 
// memory and bring the line. 

module instruction_cache
(
    input  logic                            clock,
    input  logic                            reset,
    output logic                            icache_ready,

    // Request from the core pipeline
    input  logic [`ICACHE_ADDR_WIDTH-1:0]   req_addr,
    input  logic                            req_valid,

    // Response to the core pipeline
    output logic [`ICACHE_LINE_WIDTH-1:0]   rsp_data,
    output logic                            rsp_valid,

    // Request to the memory hierarchy
    output logic                            req_valid_miss,
    output memory_request_t                 req_info_miss,

    // Response from the memory hierarchy
    input  logic [`ICACHE_LINE_WIDTH-1:0]   rsp_data_miss,
    input  logic                            rsp_valid_miss
);

//////////////////////////////////////////////////
// Instruction Cache arrays: tag, data and valid
logic [`ICACHE_LINE_WIDTH-1:0]  instMem_data,instMem_data_ff [`ICACHE_NUM_WAYS-1:0];
logic [`ICACHE_TAG_RANGE]       instMem_tag, instMem_tag_ff  [`ICACHE_NUM_WAYS-1:0];
logic [`ICACHE_NUM_WAYS-1:0]    instMem_valid, instMem_valid_ff;

//  CLK        DOUT         DIN         
`FF(clock, instMem_data_ff, instMem_data)
`FF(clock, instMem_tag_ff , instMem_tag )

//      CLK    RST    DOUT               DIN           DEF
`RST_FF(clock, reset, instMem_valid_ff, instMem_valid, '0)

//////////////////////////////////////////////////
// Control signals 
logic tag_miss; // asserted when there is a miss on the instr. cache
logic icache_hit;
logic [`ICACHE_NUM_WAY_RANGE]       hit_way; 
logic [`ICACHE_TAG_RANGE]           req_addr_tag;
logic [`ICACHE_NUM_WAY_RANGE]       req_addr_pos; // Position of the data in case there is a hit on tag array

//////////////////////////////////////////////////
// Position of the victim to be evicted from the I$
logic [`ICACHE_NUM_SET_RANGE]       req_addr_set,miss_icache_set_ff;  
logic [`ICACHE_NUM_WAY_RANGE]       miss_icache_way, miss_icache_way_ff; 

//         CLK    RST    EN        DOUT                DIN              DEF
`RST_EN_FF(clock, reset, tag_miss, miss_icache_set_ff, req_addr_set,    '0)
`RST_EN_FF(clock, reset, tag_miss, miss_icache_way_ff, miss_icache_way, '0)

//////////////////////////////////////////////////
// Ready signal to stall the pipeline if ICache is busy
logic icache_ready_next;

//      CLK    RST    DOUT          DIN                DEF
`RST_FF(clock, reset, icache_ready, icache_ready_next, '0)


integer iter;

always_comb
begin
    // Mantain values for next clock
    instMem_valid       = instMem_valid_ff;
    instMem_tag         = instMem_tag_ff;
    instMem_data        = instMem_data_ff;
    icache_ready_next   = icache_ready;

    // There is a miss if the tag is not stored
    req_addr_tag    = req_addr[`ICACHE_TAG_ADDR_RANGE];
    req_addr_set    = req_addr[`ICACHE_SET_ADDR_RANGE]; 
    
    icache_hit      = 1'b0;
    hit_way         = '0;
    req_addr_pos    = '0; 

    // Look if the tag is on the cache
    for (iter = 0; iter < `ICACHE_WAYS_PER_SET; i++)
    begin
        if ((instMem_tag[iter + req_addr_set*`ICACHE_WAYS_PER_SET]   == req_addr_tag) &
             instMem_valid[iter + req_addr_set*`ICACHE_WAYS_PER_SET] == 1'b1)
        begin
            req_addr_pos      = iter + req_addr_set*`ICACHE_WAYS_PER_SET;
            icache_hit        = 1'b1;
            hit_way           = iter;
        end
    end
    
    // If there is a request from the fetch stage and there is no hit, we
    // have a miss
    tag_miss = (req_valid & icache_hit) ? 1'b0 : 1'b1;

    // If there is a miss we send a request to main memory to get the line
    if ( tag_miss )
    begin
        req_info_miss.addr              = req_addr;
        req_info_miss.is_store          = 1'b0;
        req_valid_miss                  = 1'b1;
        icache_ready_next               = 1'b0;
    end

    // We wait until we receive the response from main memory. Then, we update
    // the tag, data and valid information for the position related to that
    // tag 
    if (rsp_valid_miss)
    begin
        miss_icache_pos = miss_icache_way_ff + miss_icache_set_ff*`ICACHE_WAYS_PER_SET;
        instMem_tag[miss_icache_pos]   = req_addr_tag;
        instMem_data[miss_icache_pos]  = rsp_data_miss;
        instMem_valid[miss_icache_pos] = 1'b1; 
        icache_ready_next              = 1'b1;
    end
end

assign rsp_data  = ( rsp_valid_miss ) ? instMem_data[miss_icache_pos] : // if there is a response for a miss
                   ( !tag_miss      ) ? instMem_data_ff[req_addr_pos]    : // if we hit on the first access
                                        '0;                             // default

assign rsp_valid = ( rsp_valid_miss ) ? 1'b1 : // if there is a response for a miss
                   ( !tag_miss      ) ? 1'b1 : // if we hit on the first access
                                        1'b0;  // default


logic [`ICACHE_NUM_SET_RANGE] update_set;  
logic [`ICACHE_NUM_WAY_RANGE] update_way;  

assign update_set = (rsp_valid_miss) ? miss_icache_set_ff :
                    (icache_hit)     ? req_addr_set       :
                    '0;

assign update_way = (rsp_valid_miss) ? miss_icache_way_ff :
                    (icache_hit)     ? hit_way            :
                    '0;              
// This module returns the oldest way accessed for a given set and updates the
// the LRU logic when there's a hit on the I$ or we bring a new line                        
icache_lru
icache_lru
(
    // System signals
    .clock              ( clock             ),
    .reset              ( reset             ),

    // Info to select the victim
    .victim_req         ( tag_miss          ),
    .victim_set         ( req_addr_set      ),

    // Victim way
    .victim_way         ( miss_icache_way   ),

    // Update the LRU logic
    .update_req         ( rsp_valid_miss |
                          icache_hit        ),
    .update_set         ( update_set        ),
    .update_way         ( update_way        )
);

endmodule 