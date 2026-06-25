# cg-agent-kit - an MCP server for FPGA design in C⏚

[![ci](https://github.com/Neosyn-Logic/cg-agent-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/Neosyn-Logic/cg-agent-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Give an AI agent the ability to design real hardware. `cg-agent-kit` is a
[Model Context Protocol](https://modelcontextprotocol.io) server that drives the
open-source **C⏚ Verilog compiler** - so an agent writes a C-like HDL, and the
server compiles, checks, generates Verilog, and synthesis-checks it against the
*real* toolchain instead of hallucinating Verilog that doesn't build.

C⏚ ("C-Ground") is a hardware description language with C-like syntax that
compiles to clean, standard Verilog. The compiler is open source at
**[github.com/Neosyn-Logic/cg-compiler](https://github.com/Neosyn-Logic/cg-compiler)**.

## Tools

| Tool | What it does |
|------|--------------|
| `cg_check` | Compile + validate C⏚; structured diagnostics (file:line, the fix) |
| `cg_generate_verilog` | Emit synthesizable Verilog |
| `cg_simulate` | Simulate a design (`iverilog` backend, or the commercial fast sim) |
| `cg_synth` | Yosys-synthesize the Verilog: REAL / FOLDED / SUSPECT verdict + cell count |
| `cg_example` | Scored lookup into a curated, **validated-code dictionary** (18 entries) |
| `cg_suggest_for_error` | Map a compiler error to the recipe with the fix pattern |
| `cg_fsm` / `cg_graph` | A task's compiled state machine / a network's graph |
| `cg_docs` | C⏚ language + patterns reference |

The kit's organizing idea: agents **seed-and-adapt** from validated code and
**verify against the real compiler** at every step - not invent-from-scratch.

## Open vs commercial

This kit and the compiler it drives are open. The **fast (bytecode) cycle-accurate
simulator** is part of the commercial Neosyn SDK - so `cg_simulate`'s default
`bytecode` backend asks you to upgrade, while the **`iverilog` backend works
fully** (generate Verilog + run Icarus Verilog). Everything else -
check, generate, synth, the dictionary, docs - runs entirely on the open compiler.
More at [neosyn.io/open](https://neosyn.io/open).

## Setup

1. Build the open compiler jar from
   [cg-compiler](https://github.com/Neosyn-Logic/cg-compiler):
   ```bash
   cd releng && mvn install -DskipTests && cd lsp-server && mvn package
   ```
2. Point the kit at it and install the MCP dependency:
   ```bash
   export CG_JAR=/path/to/cg-compiler/releng/lsp-server/target/cg-language-server.jar
   pip install -r requirements.txt
   ```
3. (Optional, for `cg_synth` / the `iverilog` backend) install `yosys` and
   `iverilog`.

## Run

As an MCP server (for Claude Desktop, Cursor, or any MCP client):

```bash
python cg_mcp_server.py
```

Or call the verification functions directly - they use only the stdlib:

```python
import cg_mcp_server as cg
print(cg.check(open("Counter.cg").read()))
print(cg.generate(open("Counter.cg").read()))
```

See `examples/` for 18 validated C⏚ designs and `cg_context.md` /
`cg_riscv.md` for the language + CPU-pattern references the `cg_docs` tool serves.

## License

MIT - see [LICENSE](LICENSE). C⏚ began as the Synflow Cx toolchain.
