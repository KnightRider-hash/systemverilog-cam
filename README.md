# CAM (Content-Addressable Memory) SystemVerilog Testbench

A self-checking SystemVerilog testbench for a 4-entry Content-Addressable Memory (CAM). The design supports writing 32-bit words into one of four addressable slots and searching for a 32-bit word across all slots, returning a hit/miss flag and the matching address.

## Design Under Test (DUT)

`cam` — a 4-entry, 32-bit-wide content-addressable memory.

**Interface (`cambus`)**

| Signal    | Direction | Width | Description                              |
|-----------|-----------|-------|-------------------------------------------|
| `clk`     | in        | 1     | Clock                                     |
| `rst`     | in        | 1     | Synchronous reset (clears all 4 entries)  |
| `wr`      | in        | 1     | Write enable                              |
| `wr_adr`  | in        | 2     | Write address (selects one of 4 slots)    |
| `din`     | in        | 32    | Data to write                             |
| `sword`   | in        | 32    | Search word                               |
| `adr`     | out       | 2     | Address of first matching entry           |
| `emp`     | out       | 1     | Search result: `0` = Found, `1` = Miss    |

**Behavior**

- On `rst`, all 4 storage entries are cleared to zero.
- On `wr = 1`, `din` is written into `x[wr_adr]` on the next clock edge.
- Combinationally, `sword` is compared against all 4 entries (priority order 0→3). If a match is found, `adr` reflects the matching slot and `emp = Found (0)`. Otherwise `emp = Miss (1)`.

## Testbench Architecture

The environment follows a classic layered (driver/monitor/scoreboard) verification methodology built from plain SystemVerilog classes and mailboxes — no UVM base classes required.

```
CamGenerator ──(mailbox: gen_to_drv)──> CamDriver ──> DUT (cam) ──> CamMonitor ──(mailbox: mon_to_sb)──> CamScoreboard
```

### Components

- **`CamTransaction`** — Randomizable transaction class carrying `wr`, `wr_adr`, `din`, `sword`, and the DUT's `emp`/`adr` outputs. `din` and `sword` use a `dist` constraint weighted toward four "magic" values plus a uniformly random 32-bit value.

- **`CamGenerator`** — Produces a directed + random stimulus sequence in three phases:
  1. **Phase 1 – Known writes:** writes 4 known data values to addresses 0–3.
  2. **Phase 2 – Known searches:** searches for each of the 4 values just written.
  3. **Phase 3 – Random testing:** 20 fully randomized transactions.

- **`CamDriver`** — Pulls transactions from `gen_to_drv` and drives them onto the `cambus` interface signals on each clock edge.

- **`CamMonitor`** — Passively samples the `cambus` interface after each clock edge (with a small delta delay to account for `<=` update timing) and forwards observed transactions to the scoreboard via `mon_to_sb`.

- **`CamScoreboard`** — Maintains a "golden model" (`perfect_cam`, a 4-entry software array) that mirrors the DUT's writes. On search transactions, it computes the expected `emp` result and compares it against the DUT's actual output, reporting `PASS`/`FAIL` via `$display`/`$error`.

- **`CamEnvironment`** — Instantiates and wires together the generator, driver, monitor, and scoreboard (including their mailboxes and the shared virtual interface), then runs them concurrently via `fork ... join_none`.

- **`CamTest`** — Top-level test class that builds the environment and starts it.

- **`top_tb`** — Top-level testbench module: instantiates the `cambus` interface and the `cam` DUT, generates the clock, dumps waveforms (`dump.vcd`), and kicks off `CamTest`.

## Simulator Compatibility

This testbench relies on SystemVerilog OOP constructs — classes, mailboxes, and `randomize()`/constraints — which require a simulator with full SystemVerilog (IEEE 1800) support:

- **Questa/ModelSim, VCS, Xcelium** — full support, recommended.
- **Vivado Simulator (XSIM)** — supports classes, mailboxes, and randomization; confirmed working for this testbench.
- **Verilator** — partial/growing support for SV classes; may work depending on version, but not guaranteed for mailboxes.
- **Icarus Verilog** — does **not** support classes, mailboxes, or `randomize()`. It will fail to compile this testbench as-is. Icarus can still be used to compile/elaborate the DUT (`cam` + `cambus`) on its own, or with a simplified procedural (non-class-based) testbench.

## Running the Simulation

Tested with **Vivado Simulator (XSIM)**:

```bash
xvlog -sv Sim/*.sv Src/*.sv
xelab top_tb -s top_sim
xsim top_sim -runall
```

Or with Questa/VCS/Xcelium:

```bash
vlog Sim/*.sv Src/*.sv
vsim -c top_tb -do "run -all"
```

(Substitute your simulator's equivalent compile/elaborate/run commands as needed.)

Waveforms are dumped to `dump.vcd` in `result/` and can be viewed with GTKWave:

```bash
gtkwave result/dump.vcd
```

## Sample Output

```
Starting the CAM Test...
Starting Phase 1: Writing known data...
[SCOREBOARD] Wrote 11223344 to address 0
...
Starting Phase 2: Searching known data...
[PASS] Searched for deadbeef. Hardware emp matched perfectly.
...
Starting Phase 3: Random testing...
[PASS] Searched for a1b2c3d4. Hardware emp matched perfectly.
```

Any mismatch between the DUT's `emp` output and the scoreboard's expected value is reported as `[FAIL]` via `$error`.

## Repository Structure

```
.
├── Sim/          # DUT + cambus interface
├── Src/          # Testbench classes + top_tb module
├── result/       # Waveform dumps (dump.vcd)
└── README.md
```

## Possible Extensions

- Add functional coverage (covergroups) for address/data distribution and write-then-search sequences.
- Randomize reset assertion mid-test.
- Add a checker for the `adr` output on hits, not just `emp`.
- Parameterize CAM depth/width instead of hardcoding 4 entries × 32 bits.
