# µWatt‑Infer SoC

An open-source SoC for small-scale language model inference on the edge, built around the 64‑bit Microwatt POWER ISA core plus a custom ML accelerator, targeting the SKY130 PDK with a fully open EDA flow.

## Summary

µWatt‑Infer will be a fully open-source SoC dedicated to efficient, small‑scale language model inference at the edge. A 64‑bit Microwatt core orchestrates the accelerator that targets the compute‑intensive Machine learning operations: matrix multiplication, softmax, and layer normalization.

## Project Description & Goals

The design offloads heavy inference kernels to a dedicated accelerator while Microwatt manages control flow, data movement, and I/O. This hybrid CPU/accelerator architecture balances performance with area/power limits on SKY130.

### Key Goals

- Design a specialized accelerator for Inference workloads (MatMul, Softmax, LayerNorm), leveraging open IP (e.g., systolic arrays) adapted for SKY130.
- Integrate tightly with Microwatt via a standard Wishbone bus for control and data movement.
- Use a fully open EDA flow from RTL simulation (GHDL) through synthesis (Yosys) and P&R (OpenLane).
- Constrain for SKY130 manufacturability with realistic area, timing, and power budgets; produce a fabrication‑viable GDSII.
- Provide clear documentation: architecture diagrams, verification plan and a reproducibility guide.

## Project Motivation

The µWatt‑Infer SoC project aims to make efficient, small‑scale language model inference accessible and reproducible for everyone. By combining a proven open-source Microwatt POWER ISA CPU with a custom accelerator, the design targets the unique challenges of running AI workloads at the edge—where power, area, and cost are tightly constrained.

This project showcases how open hardware can drive innovation in edge AI, foster education, and empower a broader community to explore, prototype, and advance the state of low‑cost, energy‑efficient inference systems.

## Technical Deep Dive

### System Architecture

Components:

- Microwatt CPU core (controller)
- Inference accelerator: systolic MatMul, vector ALU, and SFU (Softmax/LayerNorm)
- On‑chip SRAM for weights/activations/code (8–16 KB feasible target on SKY130)
- Wishbone interconnect (CPU ↔ SRAM ↔ accelerator)
- UART peripheral for I/O and demo

### Accelerator Design

- Systolic array for MatMul (adapt open designs; right‑size for area).  
- Vector ALU for element‑wise ops.  
- Special Function Unit (Softmax/LayerNorm) using LUTs and iterative methods.  
- Target performance: ~5–10 inferences/sec on a tiny model within SKY130 limits.  
- Bottlenecks: SRAM capacity and Wishbone latency—mitigated via careful tiling and on‑chip data reuse.

## Action Plan

1. Select a reference tiny model (e.g., char‑rnn or micro‑transformer) to drive concrete memory/throughput targets.  
2. Identify candidate open IP (systolic array, softmax/LN blocks) for adaptation.  
3. Draft a plan for RTL, verification, firmware, integration, and P&R.  
4. Stand up CI for simulation and linting; document reproducible build steps.

## Repository & Build Notes

- This repository targets the OpenFrame/Caravel ecosystem and SKY130.  
- Tooling: GHDL, Yosys, OpenLane, KLayout, Magic.  
- Reproducible setup and full build instructions will be published as the design lands in `docs/`.

## License

Apache‑2.0. See `LICENSE`.

## Acknowledgments

Microwatt (POWER ISA), OpenLane/OpenROAD, SkyWater SKY130 PDK, and the broader open‑hardware community.
