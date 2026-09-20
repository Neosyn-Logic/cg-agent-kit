"""Compatibility shim for `neosyn_fpga_mcp.cg_mcp_server`.

Two distinct jobs, and the first version of this file only did one of them.

IMPORT: re-export the module object itself, so `cg_agent_kit.cg_mcp_server` is
the SAME object as the real module -- not a copy with its own state. Patching,
reloading or reaching for a private helper through either name behaves
identically.

EXECUTION: `python -m cg_agent_kit.cg_mcp_server` must actually start the
server. That is the invocation MCP host configs use, and it is the whole reason
this shim exists.

⚠️ The second does NOT follow from the first, which is how it shipped broken.
Under `-m`, runpy executes THIS file with `__name__ == "__main__"`. Importing the
real module does not run its own `if __name__ == "__main__": main()` guard --
at import time its `__name__` is `neosyn_fpga_mcp.cg_mcp_server`, not
`__main__`. So the import succeeded, `sys.modules` was rebound, the file fell
off the end, and the server started nothing: no output, exit 0. Two AccelOne
turns ran with zero cg tools before the cause was found in a service journal.

An import-based test passes cleanly in that state. Only running the entry point
catches it -- see `TestTheShimActuallyRunsTheServer`.
"""
import sys as _sys

from neosyn_fpga_mcp import cg_mcp_server as _real

# Make the two module names the SAME object.
_sys.modules[__name__] = _real

if __name__ == "__main__":
    # The rebind above does not change this frame's globals, so this still fires.
    _real.main()
