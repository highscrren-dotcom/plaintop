#!/usr/bin/env python3
"""notes.py inside the service's process: the /notes endpoint of PROTOCOL.md.

On Plasma the calendar runs calendar/package/contents/code/notes.py through the
executable engine, one process per call. On Windows the service answers the same calls
itself: the script is loaded once with importlib and its main() is called with the
arguments as they are — nothing is quoted, nothing passes through a shell — with stdout
captured, so the JSON document comes back as text.

    run(["dump", "--upcoming", "2"])   → ('{"days": …}\\n', 0)

One call at a time: redirecting stdout is process-wide, and the script writes its caches
and the claim files without expecting a second instance of itself in the same process —
hence the module-level lock. The script lives in the repository (the path is resolved from
this file), or wherever a packaged build puts it, named in PLAINTOP_NOTES.
"""
import contextlib
import importlib.util
import io
import os
import sys
import threading
from pathlib import Path

import paths

_lock = threading.Lock()
_notes = None


def path():
    return paths.notes_py()


def load():
    """The script as a module, loaded on the first call. No __pycache__ beside it: the
    package directory is what install.sh --pack zips."""
    global _notes
    if _notes is None:
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location("plaintop_notes", path())
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _notes = module
    return _notes


def run(args):
    """notes.py's main() with these arguments → (what it printed, its exit code). A
    failure inside the script gives ("", 1) and one line on stderr; argparse's own exit —
    a bad argument, or --help — comes back with its code and text."""
    out = io.StringIO()
    with _lock:
        try:
            notes = load()
            with contextlib.redirect_stdout(out):
                code = notes.main([str(a) for a in args])
        except SystemExit as ex:
            code = ex.code if isinstance(ex.code, int) else 1
        except Exception as ex:
            print(f"notes_bridge: {type(ex).__name__}: {ex}", file=sys.stderr)
            return "", 1
    return out.getvalue(), int(code or 0)


if __name__ == "__main__":
    text, status = run(sys.argv[1:])
    sys.stdout.write(text)
    sys.exit(status)
