# Microwatt Core Hardening Guide

## Overview

This guide explains how to harden the Microwatt POWER CPU core as a macro and integrate it into the openframe project wrapper.

## Architecture

```
openframe_project_wrapper (top-level)
├── microwatt_wrapper (hardened macro) ← NEW
│   └── core (Microwatt CPU - 97K lines from VHDL)
├── vccd1_connection (power connection)
└── vssd1_connection (power connection)
```

## Step-by-Step Hardening Process

### Step 1: Generate the Verilog from VHDL

**Already done!** The Makefile target automatically generates `microwatt_core.v`:

```bash
make microwatt-core-v DOCKER=1
```

Output: `verilog/rtl/microwatt_core.v` (4.6MB, 97,970 lines)

### Step 2: Harden the `microwatt_wrapper` Macro

This synthesizes, places, and routes the Microwatt core as a standalone hard macro:

```bash
make microwatt_wrapper DOCKER=1
```

**Expected Duration**: 3-8 hours (it's a 64-bit CPU core!)

**What This Does**:
- Synthesizes ~100K lines of Verilog to standard cells
- Performs floorplanning (2850 x 3000 µm die area)
- Places ~50K-100K standard cells
- Routes all interconnects
- Generates timing-closed layout
- Produces: GDS, LEF, LIB, and SPEF files

**Monitoring Progress**:
```bash
# Watch the log in real-time
tail -f openlane/microwatt_wrapper/runs/*/logs/synthesis/1-synthesis.log

# Check current step
ls -lt openlane/microwatt_wrapper/runs/*/logs/
```

**Output Files** (automatically copied to project root):
- `gds/microwatt_wrapper.gds` - Physical layout (GDSII)
- `lef/microwatt_wrapper.lef` - Abstract layout view
- `lib/microwatt_wrapper.lib` - Timing library
- `verilog/gl/microwatt_wrapper.v` - Gate-level netlist
- `spef/multicorner/microwatt_wrapper.*.spef` - Parasitic extraction

### Step 3: Integrate as Blackbox in Top-Level Wrapper

**Already configured!** The `openframe_project_wrapper/config.json` has been updated to:

1. Remove `microwatt_core.v` and `microwatt_wrapper.v` from `VERILOG_FILES`
2. Add `microwatt_wrapper` to `VERILOG_FILES_BLACKBOX`
3. Include LEF, GDS, LIB, and SPEF files
4. Configure macro placement at (2850, 235) with orientation FN

Now run the top-level integration:

```bash
make openframe_project_wrapper DOCKER=1
```

**Duration**: ~30 minutes (much faster - just placing the pre-hardened macro)

## Configuration Details

### Microwatt Wrapper Macro (`openlane/microwatt_wrapper/config.json`)

Key settings for the large CPU design:
- **Clock Period**: 100ns (10 MHz) - relaxed for initial bringup
- **Die Area**: 2850 x 3000 µm² (~8.55mm²)
- **Core Utilization**: 30% (low to ease routing)
- **Placement Density**: 0.35 (allows room for optimization)
- **Strategy**: DELAY 3 (focus on timing over area)

### Top-Level Wrapper (`openlane/openframe_project_wrapper/config.json`)

- Treats `microwatt_wrapper` as a pre-hardened blackbox
- Places it at coordinates (2850, 235)
- Connects power/ground via `FP_PDN_MACRO_HOOKS`

## Troubleshooting

### Synthesis Issues

**Problem**: "Timing not met" errors
**Solution**: Increase `CLOCK_PERIOD` in `microwatt_wrapper/config.json`

**Problem**: "Too many cells" / out of memory
**Solution**: 
- Reduce `FP_CORE_UTIL` (try 25%)
- Increase die area
- Add more RAM to Docker

### Placement Issues

**Problem**: "Cannot place macro"
**Solution**: Adjust coordinates in `openframe_project_wrapper/macro.cfg`

**Problem**: "DRC violations"
**Solution**: 
- Increase spacing between macros
- Check for pin blockages
- Review `FP_PDN_MACRO_HOOKS` connections

## Verification

After successful hardening, verify:

```bash
# Check that all output files were created
ls -lh gds/microwatt_wrapper.gds
ls -lh lef/microwatt_wrapper.lef
ls -lh lib/microwatt_wrapper.lib
ls -lh verilog/gl/microwatt_wrapper.v

# Check the metrics report
cat openlane/microwatt_wrapper/runs/*/reports/metrics.csv

# Review timing
cat openlane/microwatt_wrapper/runs/*/reports/signoff/*-sta.rpt

# Check DRC
cat openlane/microwatt_wrapper/runs/*/reports/signoff/drc.rpt
```

## Next Steps

After successful integration:

1. **Connect Wishbone Bus**: Wire up the CPU's memory interface
2. **Add Boot ROM**: Provide initial firmware
3. **Clock Tuning**: Optimize for higher frequency (target: 25-50 MHz)
4. **Power Analysis**: Estimate power consumption
5. **Timing Closure**: Ensure no setup/hold violations
6. **DFT**: Add scan chains for manufacturing test

## Current Status

✅ VHDL-to-Verilog conversion working
✅ `microwatt_wrapper.v` with core instantiation complete
✅ OpenLane configs created for hierarchical flow
✅ Build system integration complete
⏳ Ready to harden the macro (run `make microwatt_wrapper DOCKER=1`)

## Design Files

- **Core Wrapper**: `verilog/rtl/microwatt_wrapper.v`
- **Generated Core**: `verilog/rtl/microwatt_core.v`
- **Original VHDL**: `verilog/rtl/microwatt/*.vhdl`
- **Wrapper Config**: `openlane/microwatt_wrapper/config.json`
- **Top Config**: `openlane/openframe_project_wrapper/config.json`

## References

- Microwatt Project: https://github.com/antonblanchard/microwatt
- OpenLane Documentation: https://openlane.readthedocs.io/
- SKY130 PDK: https://skywater-pdk.readthedocs.io/

