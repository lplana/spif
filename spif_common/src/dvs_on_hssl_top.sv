// -------------------------------------------------------------------------
//  dvs_on_hssl_top
//
//  DVS input to SpiNN-5 board through High-Speed Serial Link (HSSL)
//  top-level module: processor subsystem + HSSL interface +
//                    Gigabit transceiver + virtual I/O +
//                    clocks and resets
//
// -------------------------------------------------------------------------
// AUTHOR
//  lap - luis.plana@manchester.ac.uk
// -------------------------------------------------------------------------
// DETAILS
//  Created on       : 21 Oct 2020
//  Last modified on : Mon 29 Mar 09:47:33 BST 2021
//  Last modified by : lap
// -------------------------------------------------------------------------
// COPYRIGHT
//  Copyright (c) The University of Manchester, 2020.
//  SpiNNaker Project
//  Advanced Processor Technologies Group
//  School of Computer Science
// -------------------------------------------------------------------------
// TODO
//  * everything
// -------------------------------------------------------------------------

`include "dvs_on_hssl_top.h"
`include "spio_hss_multiplexer_common.h"


`timescale 1ps/1ps
module dvs_on_hssl_top
#(
  parameter TARGET_FPGA  = `FPGA_MODEL,

  parameter PACKET_BITS  = `PKT_BITS,
  parameter NUM_CHANNELS = 8,
  parameter NUM_REGS     = 1,
  parameter NUM_ENTRIES  = 16
)
(
  // differential reference clock inputs
  input  wire gt_refclk_p,
  input  wire gt_refclk_n,

`ifdef TARGET_XC7Z015
  // unused exported ports on FPGA 7z015
  inout  wire [14:0] DDR_addr,
  inout  wire  [2:0] DDR_ba,
  inout  wire        DDR_cas_n,
  inout  wire        DDR_ck_n,
  inout  wire        DDR_ck_p,
  inout  wire        DDR_cke,
  inout  wire        DDR_cs_n,
  inout  wire  [3:0] DDR_dm,
  inout  wire [31:0] DDR_dq,
  inout  wire  [3:0] DDR_dqs_n,
  inout  wire  [3:0] DDR_dqs_p,
  inout  wire        DDR_odt,
  inout  wire        DDR_ras_n,
  inout  wire        DDR_reset_n,
  inout  wire        DDR_we_n,
  inout  wire        FIXED_IO_ddr_vrn,
  inout  wire        FIXED_IO_ddr_vrp,
  inout  wire [53:0] FIXED_IO_mio,
  inout  wire        FIXED_IO_ps_clk,
  inout  wire        FIXED_IO_ps_porb,
  inout  wire        FIXED_IO_ps_srstb,
`endif

  // transceiver HSSL data ports
  input  wire gt_rxn_in,
  input  wire gt_rxp_in,
  output wire gt_txn_out,
  output wire gt_txp_out
);

  //---------------------------------------------------------------
  // internal signals
  //---------------------------------------------------------------
  // clocks and resets
  wire        tl_freerun_clk_int;
  wire        tl_reset_all_int;

  // processor subsystem signals
  wire        ps_peripheral_reset_0_int;
  wire        ps_pl_clk0_int;

  wire        axi_clk_int;
  wire        axi_resetn_int;

  wire [39:0] apb_paddr_int;
  wire        apb_penable_int;
  wire [31:0] apb_prdata_int;
  wire        apb_pready_int;
  wire        apb_psel_int;
  wire        apb_pslverr_int;
  wire [31:0] apb_pwdata_int;
  wire        apb_pwrite_int;

  wire [31:0] evt_data_int;
  wire        evt_vld_int;
  wire        evt_rdy_int;

  // register bank signals
  //  - HSSL interface control
  wire        reg_hi_int [NUM_REGS - 1:0];

  //  - packet routing table
  wire [31:0] reg_key_int   [NUM_ENTRIES - 1:0];
  wire [31:0] reg_mask_int  [NUM_ENTRIES - 1:0];
  wire  [2:0] reg_route_int [NUM_ENTRIES - 1:0];

  // HSSL interface signals
  wire        hi_clk_int;
  wire        hi_reset_int;
  wire  [1:0] hi_loss_of_sync_int;
  wire        hi_handshake_complete_int;
  wire        hi_version_mismatch_int;
  wire [15:0] hi_idsi_int;

  // Gigabit transceiver signals
  wire        gt_freerun_clk_int;
  wire        gt_reset_all_int;

  wire        gt_tx_usrclk_active_int;
  wire        gt_tx_reset_datapath_int;
  wire        gt_tx_reset_done_int;

  wire        gt_rx_reset_datapath_int;
  wire        gt_rx_reset_done_int;

  wire        gt_tx_usrclk_int;
  wire        gt_tx_usrclk2_int;
  wire [31:0] gt_tx_data_int;
  wire  [3:0] gt_tx_charisk_int;

  wire        gt_rx_usrclk_int;
  wire        gt_rx_usrclk2_int;
  wire [31:0] gt_rx_data_int;
  wire        gt_rx_commadet_int;
  wire  [3:0] gt_rx_charisk_int;
  wire  [3:0] gt_rx_disperr_int;
  wire  [3:0] gt_rx_chariscomma_int;
  wire  [3:0] gt_rx_encerr_int;
  wire        gt_rx_bufstatus_int;

  // Virtual I/O signals
  wire        vio_freerun_clk_int;
  wire        vio_reset_all_int;
  wire        vio_tx_reset_datapath_int;
  wire        vio_rx_reset_datapath_int;
  wire  [2:0] vio_loopback_int;
  //---------------------------------------------------------------


  //---------------------------------------------------------------
  // HSSL interface and transceiver clocks
  // free-running clock for the transceiver block derived from the
  // PL clock provided by the processor subsystem.
  //NOTE: (/2) avoids reconfiguration of the processor subsystem
  //PL clock
  //---------------------------------------------------------------
  wire pl_clk0_buf_int;

  reg  clk_enable_int = 1'b0;

  //NOTE: this buffer may be redundant - used only for clk_enable_int
  BUFG fast_clk (
        .I (ps_pl_clk0_int)
      , .O (pl_clk0_buf_int)
    );

  // toggle CE every clock cycle to divide p2pl_clk frequency by 2
  always @(posedge pl_clk0_buf_int)
    clk_enable_int <= ~clk_enable_int;

  //NOTE: tl_freerun_clk_int has 25% duty cycle / same pulse width as ps_pl_clk0_int
  BUFGCE slow_clk (
        .I  (ps_pl_clk0_int)
      , .CE (clk_enable_int)
      , .O  (tl_freerun_clk_int)
    );

  assign gt_freerun_clk_int = tl_freerun_clk_int;

  assign vio_freerun_clk_int = tl_freerun_clk_int;

  assign hi_clk_int  = gt_tx_usrclk2_int;

  assign axi_clk_int = gt_tx_usrclk2_int;
  //---------------------------------------------------------------


  //---------------------------------------------------------------
  // generate/buffer reset signals
  //---------------------------------------------------------------
  // buffer ps_peripheral_reset_0_int
  wire peripheral_reset_0_buf_int;
  IBUF ps_peripheral_reset_0_int_buffer (
        .I (ps_peripheral_reset_0_int)
      , .O (peripheral_reset_0_buf_int)
    );

  // global and function-specific resets
  assign tl_reset_all_int = peripheral_reset_0_buf_int || vio_reset_all_int;

  assign gt_reset_all_int = tl_reset_all_int;

  assign gt_tx_reset_datapath_int = vio_tx_reset_datapath_int;

  assign gt_rx_reset_datapath_int = vio_rx_reset_datapath_int;

  assign hi_reset_int = !gt_tx_reset_done_int || !gt_tx_usrclk_active_int;

  assign axi_resetn_int = gt_tx_reset_done_int && gt_tx_usrclk_active_int;
  //---------------------------------------------------------------


  //---------------------------------------------------------------
  // processor subsystem -
  // implements an AXI4-stream interface to the HSSL and
  // provides the free-running clock and the reset signal
  //---------------------------------------------------------------
  proc_sys ps (
      .peripheral_reset_0       (ps_peripheral_reset_0_int)
    , .pl_clk0_0                (ps_pl_clk0_int)

      // AXI interface clock and reset generated from transceiver block
    , .s_axi_aresetn_0          (axi_resetn_int)
    , .s_axi_aclk_0             (axi_clk_int)

      // APB interface to register bank
    , .APB_M_0_paddr            (apb_paddr_int)
    , .APB_M_0_penable          (apb_penable_int)
    , .APB_M_0_prdata           (apb_prdata_int)
    , .APB_M_0_pready           (apb_pready_int)
    , .APB_M_0_psel             (apb_psel_int)
    , .APB_M_0_pslverr          (apb_pslverr_int)
    , .APB_M_0_pwdata           (apb_pwdata_int)
    , .APB_M_0_pwrite           (apb_pwrite_int)

      // AXI stream interface to HSSL multiplexer
    , .AXI_STR_TXD_0_tdata      (evt_data_int)
    , .AXI_STR_TXD_0_tlast      ()
    , .AXI_STR_TXD_0_tvalid     (evt_vld_int)
    , .AXI_STR_TXD_0_tready     (evt_rdy_int)
    , .mm2s_prmry_reset_out_n_0 ()

`ifdef TARGET_XC7Z015
    // unused exported ports on 7z015
    , .DDR_addr                 (DDR_addr)
    , .DDR_ba                   (DDR_ba)
    , .DDR_cas_n                (DDR_cas_n)
    , .DDR_ck_n                 (DDR_ck_n)
    , .DDR_ck_p                 (DDR_ck_p)
    , .DDR_cke                  (DDR_cke)
    , .DDR_cs_n                 (DDR_cs_n)
    , .DDR_dm                   (DDR_dm)
    , .DDR_dq                   (DDR_dq)
    , .DDR_dqs_n                (DDR_dqs_n)
    , .DDR_dqs_p                (DDR_dqs_p)
    , .DDR_odt                  (DDR_odt)
    , .DDR_ras_n                (DDR_ras_n)
    , .DDR_reset_n              (DDR_reset_n)
    , .DDR_we_n                 (DDR_we_n)
    , .FIXED_IO_ddr_vrn         (FIXED_IO_ddr_vrn)
    , .FIXED_IO_ddr_vrp         (FIXED_IO_ddr_vrp)
    , .FIXED_IO_mio             (FIXED_IO_mio)
    , .FIXED_IO_ps_clk          (FIXED_IO_ps_clk)
    , .FIXED_IO_ps_porb         (FIXED_IO_ps_porb)
    , .FIXED_IO_ps_srstb        (FIXED_IO_ps_srstb)
`endif
    );
  //---------------------------------------------------------------


  //---------------------------------------------------------------
  // register bank (APB peripheral)
  //---------------------------------------------------------------
  hssl_reg_bank rb (
      .clk             (axi_clk_int)
    , .resetn          (axi_resetn_int)

    , .apb_psel_in     (apb_psel_int)
    , .apb_pwrite_in   (apb_pwrite_int)
    , .apb_penable_in  (apb_penable_int)

    , .apb_paddr_in    (apb_paddr_int)
    , .apb_pwdata_in   (apb_pwdata_int)
    , .apb_prdata_out  (apb_prdata_int)

    , .apb_pready_out  (apb_pready_int)
    , .apb_pslverr_out (apb_pslverr_int)

    , .reg_hssl_out    (reg_hi_int)
    , .reg_key_out     (reg_key_int)
    , .reg_mask_out    (reg_mask_int)
    , .reg_route_out   (reg_route_int)
    );
  //---------------------------------------------------------------


  //---------------------------------------------------------------
  // generate packets from events and drive the Gigabit transmitter
  //---------------------------------------------------------------
  wire [PACKET_BITS - 1:0] pkt_data_int;
  wire                     pkt_vld_int;
  wire                     pkt_rdy_int;

  wire [PACKET_BITS - 1:0] txpkt_data_int [NUM_CHANNELS - 1:0];
  wire                     txpkt_vld_int  [NUM_CHANNELS - 1:0];
  wire                     txpkt_rdy_int  [NUM_CHANNELS - 1:0];

  // make unused receivers *not* ready
  wire rxpkt_rdy_int [NUM_CHANNELS - 1:0];
  genvar chan;
  generate
    for (chan = 0; chan < NUM_CHANNELS; chan = chan + 1)
      begin : rx_not_rdy
        assign rxpkt_rdy_int[chan] = 1'b0;
      end
  endgenerate

  // assemble packets using events sent by processor subsystem
  pkt_assembler pa (
      .clk                (hi_clk_int)
    , .reset              (hi_reset_int)

      // incoming event
    , .evt_data_in        (evt_data_int)
    , .evt_vld_in         (evt_vld_int)
    , .evt_rdy_out        (evt_rdy_int)

      // assembled packet to be routed
    , .pkt_data_out       (pkt_data_int)
    , .pkt_vld_out        (pkt_vld_int)
    , .pkt_rdy_in         (pkt_rdy_int)
    );

  // route packets to HSSL channels
  pkt_router pr (
      // routing table data from register bank
      .reg_key_in         (reg_key_int)
    , .reg_mask_in        (reg_mask_int)
    , .reg_route_in       (reg_route_int)

      //  assembled packet
    , .pkt_in_data_in     (pkt_data_int)
    , .pkt_in_vld_in      (pkt_vld_int)
    , .pkt_in_rdy_out     (pkt_rdy_int)

      // outgoing packets -- can be multicast
    , .pkt_out_data_out   (txpkt_data_int)
    , .pkt_out_vld_out    (txpkt_vld_int)
    , .pkt_out_rdy_in     (txpkt_rdy_int)
    );
  //---------------------------------------------------------------


  //---------------------------------------------------------------
  // HSSL interface
  //---------------------------------------------------------------
  hssl_interface hi (
      .clk                            (hi_clk_int)
    , .reset                          (hi_reset_int)

      // routed packets to be sent to SpiNNaker
    , .txpkt_data_in                  (txpkt_data_int)
    , .txpkt_vld_in                   (txpkt_vld_int)
    , .txpkt_rdy_out                  (txpkt_rdy_int)

      // packets received from SpiNNaker
      //NOTE: currently not in use!
    , .rxpkt_data_out                 ()
    , .rxpkt_vld_out                  ()
    , .rxpkt_rdy_in                   (rxpkt_rdy_int)

      // interface status and control
    , .loss_of_sync_state_out         (hi_loss_of_sync_int)
    , .handshake_complete_out         (hi_handshake_complete_int)
    , .version_mismatch_out           (hi_version_mismatch_int)

    , .idsi_out                       (hi_idsi_int)
    , .stop_in                        (reg_hi_int[0])

      // Gigabit transmitter
    , .tx_data_out                    (gt_tx_data_int)
    , .tx_charisk_out                 (gt_tx_charisk_int)

      // Gigabit receiver
    , .rx_data_in                     (gt_rx_data_int)
    , .rx_commadet_in                 (gt_rx_commadet_int)
    , .rx_charisk_in                  (gt_rx_charisk_int)
    , .rx_disperr_in                  (gt_rx_disperr_int)
    , .rx_chariscomma_in              (gt_rx_chariscomma_int)
    , .rx_encerr_in                   (gt_rx_encerr_int)
    );
  //---------------------------------------------------------------


  //---------------------------------------------------------------
  // Gigabit transceiver and tx/rx clock modules
  //---------------------------------------------------------------
  hssl_transceiver # (
      .TARGET_FPGA                  (TARGET_FPGA)
    )
  gt (
      // GT external ports: differential clock and links
      .refclk_pad_n_in              (gt_refclk_n)
    , .refclk_pad_p_in              (gt_refclk_p)

    , .txn_out                      (gt_txn_out)
    , .txp_out                      (gt_txp_out)
    , .rxn_in                       (gt_rxn_in)
    , .rxp_in                       (gt_rxp_in)

      // free-running clock and reset
    , .freerun_clk_in               (gt_freerun_clk_int)
    , .reset_all_in                 (gt_reset_all_int)

      // block resets and done ports
    , .tx_usrclk_active_out         (gt_tx_usrclk_active_int)
    , .tx_reset_datapath_in         (gt_tx_reset_datapath_int)
    , .tx_reset_done_out            (gt_tx_reset_done_int)
    , .rx_reset_datapath_in         (gt_rx_reset_datapath_int)
    , .rx_reset_done_out            (gt_rx_reset_done_int)

      // GT transmitter ports
    , .tx_usrclk_out                (gt_tx_usrclk_int)
    , .tx_usrclk2_out               (gt_tx_usrclk2_int)
    , .tx_data_in                   (gt_tx_data_int)
    , .tx_charisk_in                (gt_tx_charisk_int)

      // GT receiver ports
    , .rx_usrclk_out                (gt_rx_usrclk_int)
    , .rx_usrclk2_out               (gt_rx_usrclk2_int)
    , .rx_data_out                  (gt_rx_data_int)
    , .rx_commadet_out              (gt_rx_commadet_int)
    , .rx_chariscomma_out           (gt_rx_chariscomma_int)
    , .rx_charisk_out               (gt_rx_charisk_int)
    , .rx_disperr_out               (gt_rx_disperr_int)
    , .rx_encerr_out                (gt_rx_encerr_int)
    , .rx_bufstatus_out             (gt_rx_bufstatus_int)

      // GT control and status ports
    , .loopback_in                  (vio_loopback_int)
    , .handshake_complete_in        (hi_handshake_complete_int)
    );
  //---------------------------------------------------------------


  //---------------------------------------------------------------
  // virtual I/O for HSSL interface and Gigabit transceiver
  //---------------------------------------------------------------
  hssl_vio vio (
      .clk              (vio_freerun_clk_int)

      // HSSL interface probes
    , .probe_in0        (hi_loss_of_sync_int)
    , .probe_in1        (hi_handshake_complete_int)
    , .probe_in2        (hi_version_mismatch_int)
    , .probe_in3        ()

      // transceiver probes
    , .probe_in4        ()
    , .probe_in5        ()
    , .probe_in6        ()
    , .probe_in7        (gt_tx_reset_done_int)
    , .probe_in8        (gt_rx_reset_done_int)
    , .probe_in9        (gt_rx_bufstatus_int)
    , .probe_in10       (gt_rx_charisk_int)
    , .probe_in11       (gt_rx_chariscomma_int)
    , .probe_in12       (gt_rx_data_int)
    , .probe_in13       (gt_tx_data_int)

      // virtual control signals
    , .probe_out0       (vio_reset_all_int)
    , .probe_out1       ()
    , .probe_out2       (vio_tx_reset_datapath_int)
    , .probe_out3       ()
    , .probe_out4       (vio_rx_reset_datapath_int)
    , .probe_out5       ()
    , .probe_out6       (vio_loopback_int)
    );
  //---------------------------------------------------------------
endmodule
