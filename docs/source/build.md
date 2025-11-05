# Build Guide for Microwatt-Infer SoC

This guide walks through building the complete Microwatt-Infer SoC from RTL to GDSII.

## Prerequisites

### Required Tools

1. **GHDL** (for Microwatt VHDL synthesis)
   - Version: 1.0 or later with LLVM backend
   - Install: `apt-get install ghdl` or build from source

2. **Yosys** (for synthesis)
   - Version: 0.30 or later with GHDL plugin
   - Install: Follow OpenLane installation

3. **OpenLane** (for place & route)
   - Version: 2024.08.15 or later
   - Install: See https://openlane.readthedocs.io/

4. **SKY130 PDK**
   - Version: Based on Open PDKs 0fe599b2 or later
   - Install via OpenLane or Volare

5. **Docker** (recommended)
   - For reproducible builds
   - Version: 20.10 or later

### Optional Tools

- **Icarus Verilog / Verilator**: For RTL simulation
- **GTKWave**: For waveform viewing
- **PowerPC64 toolchain**: For firmware compilation
  - `powerpc64le-linux-gnu-gcc`

## Environment Setup

```bash
# Set environment variables
export PDK_ROOT=/path/to/pdks
export PDK=sky130B
export OPENLANE_ROOT=/path/to/openlane
export PROJECT_ROOT=/path/to/Microwatt-InferSOC

# Activate Python virtual environment (if using)
cd $PROJECT_ROOT
python3 -m venv venv
source venv/bin/activate
pip install -r $OPENLANE_ROOT/requirements.txt
```

## Build Steps

### Step 1: Generate Microwatt Core Verilog

The Microwatt CPU core is originally written in VHDL and must be converted to Verilog:

```bash
cd $PROJECT_ROOT
make microwatt-core-v DOCKER=1
```

**Output**: `verilog/rtl/microwatt_core.v` (97,970 lines, 4.6MB)

**Duration**: ~2-5 minutes

### Step 2: Verify RTL with Testbenches

Before hardening, verify the RTL design:

```bash
# Unit tests for accelerator components
cd verilog/dv/accelerator
iverilog -o tb_systolic_array tb_systolic_array.v ../../rtl/accelerator/*.v
./tb_systolic_array

iverilog -o tb_vector_alu tb_vector_alu.v ../../rtl/accelerator/*.v
./tb_vector_alu

iverilog -o tb_sfu tb_sfu.v ../../rtl/accelerator/*.v
./tb_sfu

# Integration test (requires Microwatt core)
cd ../microwatt_soc
iverilog -o tb_microwatt_soc tb_microwatt_soc.v ../../rtl/*.v ../../rtl/**/*.v
./tb_microwatt_soc
```

### Step 3: Harden ML Accelerator Macro

Synthesize, place, and route the ML accelerator as a hard macro:

```bash
cd $PROJECT_ROOT
make ml_accelerator DOCKER=1
```

**What happens**:
1. Yosys synthesizes Verilog RTL to standard cells
2. OpenROAD performs floorplanning (1000x1000 µm)
3. Placement of ~10K-20K standard cells
4. Clock tree synthesis
5. Global and detailed routing
6. Timing analysis and optimization
7. DRC/LVS checks

**Duration**: 1-3 hours

**Output Files**:
- `gds/ml_accelerator.gds` - Physical layout (GDSII)
- `lef/ml_accelerator.lef` - Abstract layout view
- `lib/ml_accelerator.lib` - Timing library
- `verilog/gl/ml_accelerator.v` - Gate-level netlist
- `spef/multicorner/ml_accelerator.*.spef` - Parasitic extraction

**Monitoring Progress**:
```bash
# Watch synthesis log
tail -f openlane/ml_accelerator/runs/*/logs/synthesis/1-synthesis.log

# Check current step
ls -lt openlane/ml_accelerator/runs/*/logs/
```

### Step 4: Harden Microwatt SoC Macro

Integrate the hardened accelerator with Microwatt core and peripherals:

```bash
cd $PROJECT_ROOT
make microwatt_soc DOCKER=1
```

**Prerequisites**:
- ML accelerator macro completed (Step 3)
- Microwatt core Verilog available (Step 1)

**Configuration**:
- Macro placement defined in `openlane/microwatt_soc/macro.cfg`
- ML accelerator instantiated as blackbox
- SRAM controllers and interconnect synthesized

**Duration**: 3-8 hours (it's a large design!)

**Output**: Similar to Step 3, but for the full SoC

### Step 5: Harden Top-Level Wrapper

Integrate the SoC into the OpenFrame project wrapper:

```bash
cd $PROJECT_ROOT
make openframe_project_wrapper DOCKER=1
```

**What happens**:
- Instantiates hardened `microwatt_soc` macro
- Connects power rails (VCCD1, VSSD1)
- Routes GPIO signals
- Adds fill cells and tap cells
- Final DRC/LVS checks

**Duration**: 2-5 hours

**Output**: Final GDSII ready for fabrication

## Troubleshooting

### Common Issues

#### 1. GHDL Plugin Not Found

**Error**: `ERROR: This version of Yosys is built without plugin support`

**Solution**:
```bash
# Build Yosys with plugin support
cd $OPENLANE_ROOT
make build-yosys
```

#### 2. Memory Issues

**Error**: OpenLane crashes during routing

**Solution**:
- Reduce `PL_TARGET_DENSITY` in config.json
- Increase Docker memory limit
- Run on machine with more RAM (32GB+ recommended)

#### 3. Timing Violations

**Error**: Setup/hold violations in timing reports

**Solution**:
1. Increase clock period in `config.json`:
   ```json
   "CLOCK_PERIOD": 50  // Slower clock
   ```
2. Enable more aggressive optimization:
   ```json
   "GLB_RESIZER_TIMING_OPTIMIZATIONS": 1
   ```
3. Check timing reports:
   ```bash
   cat openlane/*/runs/*/reports/signoff/*.rpt
   ```

#### 4. DRC Violations

**Error**: Design Rule Check failures

**Solution**:
1. Check Magic DRC report:
   ```bash
   cat openlane/*/runs/*/reports/magic/*.rpt
   ```
2. Adjust metal layer constraints if needed
3. Increase die area to reduce congestion

### Useful Make Targets

```bash
# Clean specific macro
make clean-ml_accelerator

# Clean all macros
make clean

# Build only synthesis (no P&R)
make ml_accelerator DOCKER=1 OPENLANE_ARGS="--until synthesis"

# Interactive mode for debugging
make ml_accelerator DOCKER=1 OPENLANE_ARGS="--interactive"
```

## Verification

After hardening, verify the design:

### 1. Check Timing Reports

```bash
# Check for timing violations
grep -r "VIOLATED" openlane/*/runs/*/reports/signoff/

# View detailed timing
cat openlane/openframe_project_wrapper/runs/*/reports/signoff/*-timing.rpt
```

### 2. Check DRC/LVS

```bash
# DRC (Design Rule Check)
cat openlane/*/runs/*/reports/magic/*-drc.rpt

# LVS (Layout vs Schematic)
cat openlane/*/runs/*/reports/lvs/*.rpt
```

### 3. View Layout

```bash
# Open in KLayout
klayout openlane/openframe_project_wrapper/runs/*/results/final/gds/*.gds

# Open in Magic
magic -T $PDK_ROOT/$PDK/libs.tech/magic/sky130A.tech \
      openlane/openframe_project_wrapper/runs/*/results/final/gds/*.gds
```

## Firmware Build

To build the demo firmware:

```bash
cd firmware

# Requires powerpc64le toolchain
make CROSS_COMPILE=powerpc64le-linux-gnu-

# Outputs:
# demo.elf - ELF executable
# demo.bin - Binary image
# demo.hex - Intel HEX format
```

## Next Steps

After successful build:

1. **Pre-check**: Run `make run-precheck` for tape-out validation
2. **Simulation**: Test with gate-level netlist
3. **Tape-out**: Submit GDSII for fabrication

## Build Time Summary

| Stage | Duration | Output Size |
|-------|----------|-------------|
| Microwatt Verilog | 2-5 min | 4.6 MB |
| ML Accelerator | 1-3 hours | ~500 MB |
| SoC Integration | 3-8 hours | ~2 GB |
| Top-Level Wrapper | 2-5 hours | ~3 GB |
| **Total** | **6-16 hours** | **~6 GB** |

## References

- OpenLane Documentation: https://openlane.readthedocs.io/
- SKY130 PDK: https://skywater-pdk.readthedocs.io/
- Microwatt: https://github.com/antonblanchard/microwatt
- Efabless Caravel: https://caravel-harness.readthedocs.io/

