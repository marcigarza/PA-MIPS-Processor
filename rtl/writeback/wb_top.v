`include "soc.vh"

module wb_top
(
    // System signals
    input   logic                               clock,
    input   logic                               reset,

    // Exceptions
    input   fetch_xcpt_t                        xcpt_fetch,
    input   decode_xcpt_t                       xcpt_decode,
    input   alu_xcpt_t                          xcpt_alu,    
    input   cache_xcpt_t                        xcpt_cache,    
     
    // Request from cache stage
    input   logic                               cache_req_write_rf,
    input   logic [`REG_FILE_ADDR_RANGE]        cache_req_dest_rf,
    input   logic [`DCACHE_MAX_ACC_SIZE-1:0]    cache_req_rsp_data,
    input   logic [`PC_WIDTH-1:0]               cache_req_pc,

    // Request to RF
    output  logic [`REG_FILE_DATA_RANGE] 		req_to_RF_data,
    output  logic 				                req_to_RF_writeEn,
    output  logic [`REG_FILE_ADDR_RANGE] 		req_to_RF_dest,

    // Exceptions values to be stored on the RF
    output  logic 				                xcpt_valid,
    output  xcpt_type_t                         xcpt_type,
    output  logic [`PC_WIDTH_RANGE] 		    rmPC,
    output  logic [`REG_FILE_XCPT_ADDR_RANGE] 	rmAddr,

    // Request from cache stage 
    input   logic                               cache_tlb_req_valid,
    input   logic                               cache_tlb_id,
    input   tlb_req_info_t                      cache_tlb_req_info,

    // Request from WB to TLB
    output  logic                               new_tlb_entry,
    output  logic                               new_tlb_id,
    output  tlb_req_info_t                      new_tlb_info
);

////////////////////////////
// TLB new entry request
always_comb
begin
    new_tlb_entry   = cache_tlb_req_valid;
    new_tlb_id      = cache_tlb_id;
    new_tlb_info    = cache_tlb_req_info;
end

///////////////////////////
// Exception priorities
always_comb
begin
    xcpt_valid  = 1'b0;
    xcpt_type   = reserved;
    rmAddr      = '0;
    rmPC        = '0;

    if (  xcpt_fetch.xcpt_itlb_miss 
        | xcpt_fetch.xcpt_bus_error )
    begin
        xcpt_valid  = 1'b1;
        xcpt_type   = (xcpt_fetch.xcpt_itlb_miss) ? iTlb_miss : fetch_bus_error;
        rmPC        = xcpt_fetch.xcpt_pc; 
        rmAddr      = xcpt_fetch.xcpt_addr_val;
    end
    else if (xcpt_decode.xcpt_illegal_instr)
    begin
        xcpt_valid  = 1'b1;
        xcpt_type   = illegal_instr;
        rmPC        = xcpt_decode.xcpt_pc;
    end
    else if (xcpt_alu.xcpt_overflow)
    begin
        xcpt_valid  = 1'b1;
        xcpt_type   = overflow;
        rmPC        = xcpt_alu.xcpt_pc;
    end
    else if (  xcpt_cache.xcpt_addr_fault 
             | xcpt_cache.xcpt_dtlb_miss
             | xcpt_cache.xcpt_bus_error)
    begin
        xcpt_valid  = 1'b1;
        xcpt_type   = ( xcpt_cache.xcpt_addr_fault ) ? cache_addr_fault :
                      ( xcpt_cache.xcpt_dtlb_miss  ) ? dTlb_miss        :
                                                       cache_bus_error;  
        rmPC        = xcpt_cache.xcpt_pc;
        rmAddr      = xcpt_cache.xcpt_addr_val;
    end
end

////////////////////////////
// RF write requests
always_comb
begin
   req_to_RF_data    = cache_req_rsp_data;
   req_to_RF_writeEn = cache_req_write_rf;
   req_to_RF_dest    = cache_req_dest_rf;
end

endmodule
