# Third-party files

The MIT license in `LICENSE` covers my own work in this repository. It does not cover the files below, which keep their own licenses.

## `sky130hd/`

The Sky130 HD platform files that the synthesis, timing and place-and-route flows read. I took them from the `test/sky130hd/` directory of the
OpenROAD project (https://github.com/The-OpenROAD-Project/OpenROAD), which is distributed under the BSD 3-Clause License, Copyright (c) 2018-2025,
The OpenROAD Authors, by way of my Full-Adder project. Two of them differ from OpenROAD's copies: `sky130hd.tracks` and `sky130hd.vars`.

The cell data in that folder (`sky130_fd_sc_hd__tt_025C_1v80.lib`, `sky130hd_tt.lib`, `sky130hd_std_cell.lef`, `sky130_fd_sc_hd_merged.lef` and
`sky130hd.tlef`) comes from the SkyWater SKY130 PDK, Copyright 2020 The SkyWater PDK Authors, licensed under the Apache License, Version 2.0
(https://www.apache.org/licenses/LICENSE-2.0). The LEF files carry that notice in their headers.

## Tools that are used but not included

Verilator, Yosys, OpenSTA, OpenROAD and GTKWave are run by the scripts here, but none of their code is in this repository.
