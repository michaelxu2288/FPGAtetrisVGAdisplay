// ============================================================================
// fpga_tetris_ethernet.sv
// ----------------------------------------------------------------------------
// Makeshift SystemVerilog Ethernet subsystem skeleton for Spartan‑7 FPGA
// Multiplayer Tetris project (MicroBlaze + VGA + Audio + Ethernet)
// ----------------------------------------------------------------------------
// ‣ Supports two alternative back‑ends:
//      1. WIZnet W5500 (SPI‑based) Pmod NIC interface
//      2. AXI Ethernet Lite MAC (MII) + external PHY
// ‣ Provides UDP/IPv4 packetizer + depacketizer stubs
// ‣ AXI4‑Lite slave register file for MicroBlaze configuration
// ‣ Interrupt lines for RX‑packet‑ready, TX‑done, link status
//
// ============================================================================

`timescale 1ns / 1ps

package net_pkg;
   // -----------------------------------------------------------------
   // Common constants and typedefs
   // -----------------------------------------------------------------
   typedef logic [47:0] mac_t;
   typedef logic [31:0] ip_t;
   typedef logic [15:0] port_t;
   typedef logic [15:0] len_t;

   typedef enum logic [1:0] {
      ETH_NONE,
      ETH_W5500_SPI,
      ETH_AXI_MAC
   } eth_backend_t;
endpackage : net_pkg

import net_pkg::*;

// -----------------------------------------------------------------------------
// Top‑level wrapper: exposes AXI‑Lite slave interface to MicroBlaze SoC
// -----------------------------------------------------------------------------
module tetris_net_top #(
   parameter mac_t LOCAL_MAC  = 48'h02_00_00_00_00_01,
   parameter ip_t  LOCAL_IP   = 32'hC0A8_000A,  // 192.168.0.10
   parameter port_t LOCAL_UDP = 16'd51000,
   parameter eth_backend_t BACKEND = ETH_W5500_SPI
)(
   // ---------- Clocks / Resets ----------
   input  logic         clk_axi,
   input  logic         rstn_axi,

   // ---------- AXI4‑Lite Slave (to MicroBlaze) ----------
   input  logic [31:0]  s_axi_awaddr,
   input  logic         s_axi_awvalid,
   output logic         s_axi_awready,

   input  logic [31:0]  s_axi_wdata,
   input  logic [3:0]   s_axi_wstrb,
   input  logic         s_axi_wvalid,
   output logic         s_axi_wready,

   output logic [1:0]   s_axi_bresp,
   output logic         s_axi_bvalid,
   input  logic         s_axi_bready,

   input  logic [31:0]  s_axi_araddr,
   input  logic         s_axi_arvalid,
   output logic         s_axi_arready,

   output logic [31:0]  s_axi_rdata,
   output logic [1:0]   s_axi_rresp,
   output logic         s_axi_rvalid,
   input  logic         s_axi_rready,

   // ---------- Interrupt to MicroBlaze ----------
   output logic         intr_net,

   // ---------- Backend‑specific I/O ----------
   // W5500 SPI signals (used when BACKEND == ETH_W5500_SPI)
   output logic         spi_sck,
   output logic         spi_mosi,
   input  logic         spi_miso,
   output logic         spi_csn,
   input  logic         w5500_int_n,

   // AXI Ethernet Lite MII signals (used when BACKEND == ETH_AXI_MAC)
   output logic         mii_tx_clk,
   output logic [3:0]   mii_txd,
   output logic         mii_tx_en,
   input  logic         mii_rx_clk,
   input  logic [3:0]   mii_rxd,
   input  logic         mii_rx_dv,
   output logic         mii_mdc,
   inout  logic         mii_mdio
);

   // =============================================================
   // Internal buses / signals
   // =============================================================
   // Simple stream interfaces for TX and RX (payload‑only)
   typedef struct packed {
      logic        last;
      logic [7:0]  data;
   } stream_t;

   stream_t tx_stream;
   stream_t rx_stream;
   logic     tx_stream_valid, tx_stream_ready;
   logic     rx_stream_valid, rx_stream_ready;

   // Interrupt sources
   logic  irq_rx_ready, irq_tx_done, irq_link;

   // =============================================================
   // Register file (AXI4‑Lite) – controls backend and exposes status
   // =============================================================
   axi_lite_slv #(
      .ADDR_WIDTH (12),
      .DATA_WIDTH (32)
   ) u_regfile (
      .clk      (clk_axi),
      .rstn     (rstn_axi),
      .awaddr   (s_axi_awaddr[11:0]),
      .awvalid  (s_axi_awvalid),
      .awready  (s_axi_awready),
      .wdata    (s_axi_wdata),
      .wstrb    (s_axi_wstrb),
      .wvalid   (s_axi_wvalid),
      .wready   (s_axi_wready),
      .bresp    (s_axi_bresp),
      .bvalid   (s_axi_bvalid),
      .bready   (s_axi_bready),
      .araddr   (s_axi_araddr[11:0]),
      .arvalid  (s_axi_arvalid),
      .arready  (s_axi_arready),
      .rdata    (s_axi_rdata),
      .rresp    (s_axi_rresp),
      .rvalid   (s_axi_rvalid),
      .rready   (s_axi_rready),
      // Custom register outputs (write‑only for simplicity)
      .reg_tx_data   (/*TODO*/),
      .reg_tx_strobe (/*TODO*/)
   );

   // =============================================================
   // Backend selection
   // =============================================================
   generate
      if (BACKEND == ETH_W5500_SPI) begin : gen_w5500
         // ------------------------------------------------------
         // 1) SPI Master (AXI‑Stream like interface to W5500)
         // ------------------------------------------------------
         spi_master #(
            .CLK_DIV (4) // Generates SCK = clk_axi/8 ~ 12.5 MHz @100 MHz
         ) u_spi (
            .clk        (clk_axi),
            .rstn       (rstn_axi),
            .miso       (spi_miso),
            .mosi       (spi_mosi),
            .sck        (spi_sck),
            .cs_n       (spi_csn),
            // Stream interface to W5500 controller
            .tx_data    (tx_stream.data),
            .tx_valid   (tx_stream_valid),
            .tx_ready   (tx_stream_ready),
            .rx_data    (rx_stream.data),
            .rx_valid   (rx_stream_valid),
            .rx_ready   (rx_stream_ready)
         );

         // ------------------------------------------------------
         // 2) W5500 Register/Socket Controller
         // ------------------------------------------------------
         w5500_ctrl u_w5500 (
            .clk          (clk_axi),
            .rstn         (rstn_axi),
            .spi_tx_data  (tx_stream.data),
            .spi_tx_valid (tx_stream_valid),
            .spi_tx_ready (tx_stream_ready),
            .spi_rx_data  (rx_stream.data),
            .spi_rx_valid (rx_stream_valid),
            .spi_rx_ready (rx_stream_ready),
            .w5500_int_n  (w5500_int_n),
            .udp_tx_data  (udp_tx_data),   // TODO: connect to UDP TX engine
            .udp_tx_valid (udp_tx_valid),
            .udp_tx_ready (udp_tx_ready),
            .udp_rx_data  (udp_rx_data),   // TODO: connect from UDP RX engine
            .udp_rx_valid (udp_rx_valid),
            .udp_rx_ready (udp_rx_ready),
            .irq_rx_ready (irq_rx_ready),
            .irq_tx_done  (irq_tx_done),
            .irq_link     (irq_link)
         );
      end else if (BACKEND == ETH_AXI_MAC) begin : gen_axi_mac
         // ------------------------------------------------------
         // 1) Instantiate Xilinx AXI Ethernet Lite IP core wrapper
         // ------------------------------------------------------
         axi_emaclite_wrapper u_mac (
            .clk          (clk_axi),
            .rstn         (rstn_axi),
            // AXI4‑Lite slave (control regs)
            .s_axi_awaddr (/*tie‑off for now*/),
            .s_axi_awvalid(1'b0),
            .s_axi_awready(/*open*/),
            // ... [control interface omitted for brevity] ...
            // MII interface
            .mii_tx_clk   (mii_tx_clk),
            .mii_txd      (mii_txd),
            .mii_tx_en    (mii_tx_en),
            .mii_rx_clk   (mii_rx_clk),
            .mii_rxd      (mii_rxd),
            .mii_rx_dv    (mii_rx_dv),
            .mii_mdc      (mii_mdc),
            .mii_mdio_i   (mii_mdio),
            .mii_mdio_o   (/*TODO*/),
            .mii_mdio_t   (/*TODO*/),
            // Simple FIFO‑like streaming for data path
            .tx_data      (tx_stream.data),
            .tx_valid     (tx_stream_valid),
            .tx_ready     (tx_stream_ready),
            .rx_data      (rx_stream.data),
            .rx_valid     (rx_stream_valid),
            .rx_ready     (rx_stream_ready)
         );

         // TODO: MAC interrupt extraction → irq_rx_ready / irq_tx_done / irq_link
      end
   endgenerate

   // =============================================================
   // UDP Packetizer / Depacketizer (payload interface)
   // =============================================================
   logic [7:0] udp_tx_data;
   logic       udp_tx_valid, udp_tx_ready;
   logic [7:0] udp_rx_data;
   logic       udp_rx_valid, udp_rx_ready;

   udp_tx_engine #(
      .SRC_PORT   (LOCAL_UDP),
      .DST_PORT   (LOCAL_UDP)
   ) u_udp_tx (
      .clk          (clk_axi),
      .rstn         (rstn_axi),
      // Payload in from MicroBlaze/user logic
      .payload_data (/*connected later*/ ),
      .payload_valid(/*connected later*/ ),
      .payload_ready(/*connected later*/ ),
      // Out to backend stream
      .tx_data      (udp_tx_data),
      .tx_valid     (udp_tx_valid),
      .tx_ready     (udp_tx_ready),
      // Control (optional)
      .start        (/* TODO */)
   );

   udp_rx_engine u_udp_rx (
      .clk          (clk_axi),
      .rstn         (rstn_axi),
      .rx_data      (udp_rx_data),
      .rx_valid     (udp_rx_valid),
      .rx_ready     (udp_rx_ready),
      // Payload out to MicroBlaze/game engine
      .payload_data (/*connected later*/),
      .payload_valid(/*connected later*/),
      .payload_ready(/*connected later*/)
   );

   // =============================================================
   // Interrupt aggregation
   // =============================================================
   assign intr_net = irq_rx_ready | irq_tx_done | irq_link;

endmodule : tetris_net_top

// ============================================================================
// spi_master – very basic single‑mode SPI controller (MSB‑first)
// ============================================================================
module spi_master #(
   parameter CLK_DIV = 4 // SCK = clk/(2*CLK_DIV)
)(
   input  logic  clk,
   input  logic  rstn,
   // SPI physical lines
   input  logic  miso,
   output logic  mosi,
   output logic  sck,
   output logic  cs_n,
   // Simple streaming interface
   input  logic [7:0] tx_data,
   input  logic       tx_valid,
   output logic       tx_ready,
   output logic [7:0] rx_data,
   output logic       rx_valid,
   input  logic       rx_ready
);
   // TODO: Implement state machine for SPI TX/RX
   // Placeholder: tie‑offs so design elaborates
   assign sck       = 1'b0;
   assign mosi      = 1'b0;
   assign cs_n      = 1'b1;
   assign tx_ready  = 1'b1;
   assign rx_data   = 8'h00;
   assign rx_valid  = 1'b0;
endmodule : spi_master

// ============================================================================
// w5500_ctrl – High‑level controller for W5500 registers & UDP sockets
// ============================================================================
module w5500_ctrl (
   input  logic       clk,
   input  logic       rstn,
   // SPI streaming
   output logic [7:0] spi_tx_data,
   output logic       spi_tx_valid,
   input  logic       spi_tx_ready,
   input  logic [7:0] spi_rx_data,
   input  logic       spi_rx_valid,
   output logic       spi_rx_ready,
   input  logic       w5500_int_n,
   // UDP stream interface
   input  logic [7:0] udp_tx_data,
   input  logic       udp_tx_valid,
   output logic       udp_tx_ready,
   output logic [7:0] udp_rx_data,
   output logic       udp_rx_valid,
   input  logic       udp_rx_ready,
   // Interrupt outputs
   output logic       irq_rx_ready,
   output logic       irq_tx_done,
   output logic       irq_link
);
   // TODO: Implement register FSM, socket open, TX/RX buffer mgmt
   assign spi_tx_data  = 8'h00;
   assign spi_tx_valid = 1'b0;
   assign spi_rx_ready = 1'b1;
   assign udp_tx_ready = 1'b1;
   assign udp_rx_data  = 8'h00;
   assign udp_rx_valid = 1'b0;
   assign irq_rx_ready = 1'b0;
   assign irq_tx_done  = 1'b0;
   assign irq_link     = 1'b0;
endmodule : w5500_ctrl

// ============================================================================
// udp_tx_engine – Skeleton for constructing UDP + IPv4 headers
// ============================================================================
module udp_tx_engine #(
   parameter port_t SRC_PORT = 16'd51000,
   parameter port_t DST_PORT = 16'd51000
)(
   input  logic       clk,
   input  logic       rstn,
   // Payload in
   input  logic [7:0] payload_data,
   input  logic       payload_valid,
   output logic       payload_ready,
   // Stream out to backend
   output logic [7:0] tx_data,
   output logic       tx_valid,
   input  logic       tx_ready,
   input  logic       start
);
   // TODO: Header insertion, checksum, length, FSM
   assign tx_data   = payload_data;
   assign tx_valid  = payload_valid;
   assign payload_ready = tx_ready;
endmodule : udp_tx_engine

// ============================================================================
// udp_rx_engine – Skeleton for stripping UDP / IP headers
// ============================================================================
module udp_rx_engine (
   input  logic       clk,
   input  logic       rstn,
   // Stream in from backend
   input  logic [7:0] rx_data,
   input  logic       rx_valid,
   output logic       rx_ready,
   // Payload out
   output logic [7:0] payload_data,
   output logic       payload_valid,
   input  logic       payload_ready
);
   // TODO: Header parsing, checksum verify, demultiplex
   assign payload_data  = rx_data;
   assign payload_valid = rx_valid;
   assign rx_ready      = payload_ready;
endmodule : udp_rx_engine

// ============================================================================
// axi_lite_slv – Minimal AXI‑Lite slave with register space placeholder
// ============================================================================
module axi_lite_slv #(parameter ADDR_WIDTH=12, DATA_WIDTH=32)(
   input  logic                   clk,
   input  logic                   rstn,
   // AXI lite signals ... (cut for brevity)
   input  logic [ADDR_WIDTH-1:0]  awaddr,
   input  logic                   awvalid,
   output logic                   awready,
   input  logic [DATA_WIDTH-1:0]  wdata,
   input  logic [(DATA_WIDTH/8)-1:0] wstrb,
   input  logic                   wvalid,
   output logic                   wready,
   output logic [1:0]             bresp,
   output logic                   bvalid,
   input  logic                   bready,

   input  logic [ADDR_WIDTH-1:0]  araddr,
   input  logic                   arvalid,
   output logic                   arready,
   output logic [DATA_WIDTH-1:0]  rdata,
   output logic [1:0]             rresp,
   output logic                   rvalid,
   input  logic                   rready,

   // Custom: simple TX FIFO poke
   output logic [7:0]             reg_tx_data,
   output logic                   reg_tx_strobe
);
   // TODO: Implement actual register map (read/write)
   assign awready      = 1'b1;
   assign wready       = 1'b1;
   assign bresp        = 2'b00;
   assign bvalid       = awvalid & wvalid;
   assign arready      = 1'b1;
   assign rdata        = '0;
   assign rresp        = 2'b00;
   assign rvalid       = arvalid;
   assign reg_tx_data  = wdata[7:0];
   assign reg_tx_strobe= wvalid & awvalid;
endmodule : axi_lite_slv

// ============================================================================
// axi_emaclite_wrapper – Placeholder for Xilinx generated IP
// ============================================================================
module axi_emaclite_wrapper (
   input  logic       clk,
   input  logic       rstn,
   // ... (omitted: AXI control)
   output logic       mii_tx_clk,
   output logic [3:0] mii_txd,
   output logic       mii_tx_en,
   input  logic       mii_rx_clk,
   input  logic [3:0] mii_rxd,
   input  logic       mii_rx_dv,
   output logic       mii_mdc,
   input  logic       mii_mdio_i,
   output logic       mii_mdio_o,
   output logic       mii_mdio_t,
   // Stream interface to top
   input  logic [7:0] tx_data,
   input  logic       tx_valid,
   output logic       tx_ready,
   output logic [7:0] rx_data,
   output logic       rx_valid,
   input  logic       rx_ready
);
   // TODO: Instantiate the actual EMAC Lite IP via Vivado when synthesizing
   assign tx_ready = 1'b1;
   assign rx_data  = 8'h00;
   assign rx_valid = 1'b0;
   assign mii_tx_clk = 1'b0;
   assign mii_txd    = 4'h0;
   assign mii_tx_en  = 1'b0;
   assign mii_mdc    = 1'b0;
   assign mii_mdio_o = 1'b0;
   assign mii_mdio_t = 1'b1; // tri‑state
endmodule : axi_emaclite_wrapper

// ============================================================================
// END OF FILE
// ============================================================================
