#!/usr/bin/env python3
"""Controlled failure fixture: parent and descendant wait until supervised kill."""
from pathlib import Path
import os
import sys
import time

output = Path(sys.argv[1])
child = os.fork()
name = 'descendant.pid' if child == 0 else 'leader.pid'
(output / name).write_text(str(os.getpid()) + '\n')
print(name + ' ready', flush=True)
print(name + ' stderr retained', file=sys.stderr, flush=True)
time.sleep(60)
raise SystemExit('timeout fixture unexpectedly escaped its supervisor')
