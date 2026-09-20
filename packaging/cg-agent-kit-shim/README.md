# cg-agent-kit → **neosyn-fpga-mcp**

This project was renamed. **`cg-agent-kit` is now [`neosyn-fpga-mcp`](https://pypi.org/project/neosyn-fpga-mcp/).**

```bash
pip install neosyn-fpga-mcp
```

Installing `cg-agent-kit` installs `neosyn-fpga-mcp` for you — this package
contains no code of its own. Your imports keep working either way:
`import cg_agent_kit.cg_mcp_server` and `python -m cg_agent_kit.cg_mcp_server`
both resolve to the real package, which provides the old name as an alias.

**Why the rename:** "cg" is our shorthand for C⏚, the hardware description
language this server compiles. It meant nothing to anyone searching a registry
for an FPGA tool, and the MCP registry indexes names only.

**What it is:** an MCP server that hands the C⏚ compiler to an AI agent —
check, simulate, generate Verilog, synthesise with Yosys, scaffold and lint —
so the agent writes hardware and verifies it against the real toolchain instead
of guessing.

Source: <https://github.com/Neosyn-Logic/cg-agent-kit> · MIT
