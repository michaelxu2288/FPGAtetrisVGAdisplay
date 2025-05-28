# FPGA Multiplayer Tetris on Xilinx Spartan‑7

<p align="center">
  <img src="docs/hero_image.png" width="500" alt="FPGA Tetris Screenshot"/>
</p>

A fully‑hardware‑accelerated **Tetris** implementation that marries a *MicroBlaze* soft‑processor with custom SystemVerilog graphics, audio and networking engines—now extended for **two‑player Ethernet play**.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Project Summary](#project-summary)
3. [Ethernet Interface Options](#ethernet-interface-options)
4. [Game‑State Synchronization](#game‑state-synchronization)
5. [System Architecture](#system-architecture)
6. [Block Diagram](#block-diagram)
7. [Module Descriptions](#module-descriptions)
8. [Resource & Power Statistics](#resource--power-statistics)
9. [Build & Usage](#build--usage)
10. [Potential Extensions](#potential-extensions)
11. [License](#license)

---

## Introduction

**Tetris** has been a gaming staple for decades.  This project re‑imagines the classic puzzle on an **Urbana/Spartan‑7 FPGA board** with *System‑on‑Chip* (SoC) capabilities.  Hardware acceleration guarantees consistent 60 Hz rendering while MicroBlaze firmware handles high‑level logic, input and scoring.  The latest revision adds a low‑latency **UDP/IPv4 Ethernet link** so two boards can battle head‑to‑head.  

---

## Project Summary

* **Hardware‑accelerated VGA/HDMI pipeline** driven by dual‑ROM *shape* and *palette* look‑ups.
* **MicroBlaze SoC** orchestrates gameplay, USB keyboard input (via **AXI UART‑Lite**), scorekeeping and Ethernet sockets.
* **On‑chip BRAM** holds a dual‑port 10 × 20 playfield matrix for hazard‑free concurrent reads/writes by logic and CPU.
* **Audio**: an **AXI SPI** core feeds an external codec while a **PWM IP** module drives square‑wave tones stored in a MIDI‑style ROM to reproduce the classic Tetris theme.
* **Deterministic timing**—a vsync‑derived *tick* governs piece gravity; clock‑dividers stabilise the VGA 25.175 MHz pixel clock.
* **Multiplayer**: lightweight **lwIP** (or W5500 HW stack) over **UDP** keeps two instances in lock‑step with <16 ms end‑to‑end delay.

---

## Ethernet Interface Options

| Option                               | Pros                                                          | Cons                                                                     |
| ------------------------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **Pmod NIC (WIZnet W5500)**          | Plug‑and‑play MAC + PHY; SPI bus only; built‑in TCP/UDP stack | Requires spare Pmod header; SPI limits throughput to \~50 Mbps practical |
| **AXI Ethernet Lite + External PHY** | Native AXI DMA; seamless with Xilinx lwIP; 100 Mbps line‑rate | Needs MII/RMII wiring, 25 MHz ref‑clk & magnetics                        |

*For boards without Ethernet, the W5500 Pmod is usually quickest to integrate; if a PHY is already present, **AXI EMAC Lite** offers cleaner software support.*

---

## Game‑State Synchronization

* **Protocol:** raw **UDP datagrams** for minimal overhead.
* **Payload Choices:**

  * **Input‑driven lock‑step** – transmit player keystrokes; each FPGA simulates both boards.
  * **Event‑driven versus** – send *line‑clear / garbage* events and score snapshots.
* **Timing:** network TX/RX occurs once per video frame; polling is sufficient, but packet‑arrival IRQ lines are available.
* **Reliability:** occasional missed packets are self‑correcting; critical events can be redundantly sent or ACKed at the app layer.

---

## System Architecture

```text
                 +-------------------------------------------+
                 |               MicroBlaze SoC             |
                 |  (C firmware: input, scoring, UDP, lwIP)  |
                 +----------+-------------+------------------+
                            | AXI4‑Lite   |
                            v             v
   +------------------+   +--------------+--------------+   +------------------+
   |  VGA/HDMI Core   |   |  AXI Quad SPI + W5500 NIC   |   |    PWM Audio     |
   |  (shape & colour |   |  OR AXI EMAC Lite + PHY     |   |  square‑wave gen |
   |   ROMs, scaler)  |   +--------------+--------------+   +------------------+
             |                       |                             |
   +---------v---------+     +------v------+                +------v------+
   | Dual‑Port BRAM    |<--->| UDP TX/RX  |<---------------+| USB Keyboard |
   | 10×20 playfield   |     |   Engine   | 100 Mb/s link   +-------------+
   +-------------------+     +------------+
```

---

## Module Descriptions

| Module                            | Purpose                                                      |
| --------------------------------- | ------------------------------------------------------------ |
| `tetris_core`                     | Handles gravity, rotation, collision detection, line‑clears. |
| `tetris_render`                   | Maps board + active tetromino to RGB pixel stream.           |
| `vga_controller`                  | Generates 640×480\@60 Hz timing and pixel coords.            |
| `udp_tx_engine` / `udp_rx_engine` | Insert/strip IPv4 + UDP headers, checksum and lengths.       |
| `spi_master` & `w5500_ctrl`       | Drive W5500 Pmod via 8‑bit SPI, manage socket 0 in UDP mode. |
| `axi_emaclite_wrapper`            | Thin wrapper around Xilinx AXI Ethernet Lite IP.             |
| `axi_lite_slv`                    | Memory‑mapped register file for firmware control & status.   |

*(See `/rtl/` for full SystemVerilog sources.)*

---

## Resource & Power Statistics

| Resource        | Utilisation |
| --------------- | ----------- |
| LUT             | 3 245       |
| Flip‑Flops      | 4 283       |
| BRAM 18K        | 22          |
| DSP             | 0           |
| F<sub>clk</sub> | 100 MHz     |
| Static Pwr      | 0.082 W     |
| Dynamic Pwr     | 0.422 W     |
| **Total Pwr**   | **0.504 W** |

---

## Build & Usage

1. **Clone** the repo and open **Vivado 2023.x**.
2. `make project` or import `fpga_tetris_ethernet.xpr`.
3. Select backend:

   * For **Pmod NIC**: ensure `BACKEND=ETH_W5500_SPI` in `tetris_net_top.sv` and connect the Digilent NIC100 to `JD`.
   * For **AXI EMAC**: set `BACKEND=ETH_AXI_MAC`, wire the MII pins to the external PHY, and provide a 25 MHz crystal.
4. **Generate Bitstream** → **File > Export Hardware**.
5. In **Vitis**, import the BSP, enable **lwIP v2**, and build `tetris_mb.elf`.
6. Program FPGA & run ELF; connect two boards with a crossover cable or LAN switch.
7. Enjoy *head‑to‑head* Tetris at 60 FPS!

---

## Potential Extensions

* **Difficulty ramp** – accelerate gravity over time.
* **Next‑piece preview & hold‑piece mechanic**.
* **Enhanced scoring** – combos, T‑spins.
* **PCM audio** – stream samples via I²S instead of PWM.
* **Online leaderboard** – post scores to a server via HTTP.

---

## License

Distributed under the MIT License.  See `LICENSE` for details.
