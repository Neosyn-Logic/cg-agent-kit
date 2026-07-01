<!-- mcp-name: io.neosyn/cg-agent-kit -->

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

## Install

```bash
pip install cg-agent-kit
```

Then point it at a built C⏚ compiler jar (download the prebuilt jar from
[cg-compiler releases](https://github.com/Neosyn-Logic/cg-compiler/releases/latest),
or build from source):

```bash
export CG_JAR=/path/to/cg-language-server.jar
```

(Optional, for `cg_synth` and the `iverilog` sim backend, install `yosys` and
`iverilog`.)

## Run

As an MCP server (for Claude Desktop, Cursor, Windsurf, or any MCP client):

```bash
cg-mcp-server
```

Add it to your MCP client config, e.g.:

```json
{
  "mcpServers": {
    "cg": { "command": "cg-mcp-server", "env": { "CG_JAR": "/path/to/cg-language-server.jar" } }
  }
}
```

Or call the verification functions directly from Python:

```python
from cg_agent_kit import cg_mcp_server as cg
print(cg.check(open("Counter.cg").read()))
print(cg.generate(open("Counter.cg").read()))
```

The kit bundles 18 validated C⏚ designs and the language + CPU-pattern
references the `cg_docs` tool serves.

## License

MIT - see [LICENSE](LICENSE). C⏚ began as the Synflow Cx toolchain.
