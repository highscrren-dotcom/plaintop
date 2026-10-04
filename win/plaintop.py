#!/usr/bin/env python3
"""plaintop on Windows: the service, the widgets and the tray icon, from one command.

    python win\\plaintop.py            # or pythonw, for no console window

Everything is win/service/server.py's main(): the HTTP service on 127.0.0.1:8788, then
every widget whose `shown` setting is on, and the tray. This file exists so the Startup
folder has one thing to point at — win/README.md.
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "service"))
sys.dont_write_bytecode = True

if __name__ == "__main__":
    os.chdir(HERE.parent)
    import server
    server.main()
