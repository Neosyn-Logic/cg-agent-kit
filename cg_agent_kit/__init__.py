"""Compatibility shim: this package was renamed to `neosyn_fpga_mcp`.

`cg-agent-kit` said nothing to anyone searching a registry for an FPGA tool —
"cg" is our own shorthand for C⏚. The MCP registry indexes NAMES ONLY, so the
old name was reachable only by someone who already knew it.

Everything here re-exports the real package. Existing imports and any
`python -m cg_agent_kit.cg_mcp_server` invocation keep working; new code should
use `neosyn_fpga_mcp`.
"""
from neosyn_fpga_mcp import *  # noqa: F401,F403
from neosyn_fpga_mcp import __version__  # noqa: F401
