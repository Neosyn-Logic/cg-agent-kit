"""Compatibility shim for `neosyn_fpga_mcp.cg_mcp_server`.

Re-exports the module object itself so `cg_agent_kit.cg_mcp_server` behaves as
it always did, including module-level attributes the tests and the local client
reach for (`JAR`, `_HERE`, `_EXAMPLES_DIR`, the private helpers).
"""
import sys as _sys

from neosyn_fpga_mcp import cg_mcp_server as _real

# Make the two module names the SAME object, so patching or reloading one is
# visible through the other and there is never a second copy of the state.
_sys.modules[__name__] = _real
