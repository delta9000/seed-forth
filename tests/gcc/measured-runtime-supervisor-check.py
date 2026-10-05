#!/usr/bin/env python3
"""Expected-failure supervisor proof, separate from runtime behavior results."""
from pathlib import Path
import hashlib
import json
import os
import resource
import subprocess
import sys
import tempfile
from measured_runtime_runner import Runner

ROOT = Path(__file__).resolve().parents[2]
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='measured-supervisor-', dir=ROOT / 'build-out'))
TMP = OUT / 'tmp'
TMP.mkdir()
LIMIT = 1024 ** 3
resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
runner = Runner(OUT, ROOT, TMP, LIMIT)
command = [sys.executable, str(ROOT / 'tests/gcc/measured-runtime-timeout-child.py'), str(OUT)]
try:
    runner.run(command, timeout=1)
except subprocess.TimeoutExpired:
    pass
else:
    raise AssertionError('controlled timeout was not reported as timeout')
records = json.loads((OUT / 'commands.json').read_text())
record = records[0]
assert record['arguments'] == command and record['outcome'] == 'timeout'
assert record['timeout'] and record['timeout_seconds'] == 1
assert record['memory_limit_bytes'] == LIMIT and record['returncode'] == -9
assert record['exception']['type'] == 'TimeoutExpired'
assert record['seconds'] >= 1 and record['started_utc'] and record['finished_utc']
assert record['cleanup']['complete'] and record['cleanup']['remaining'] == []
assert record['cleanup']['signal'] == 'SIGKILL'
leader = int((OUT / 'leader.pid').read_text())
descendant = int((OUT / 'descendant.pid').read_text())
assert leader == record['pid'] == record['process_group']
assert descendant in [r['pid'] for r in record['cleanup']['reaped_descendants']]
for pid in (leader, descendant):
    assert not Path('/proc', str(pid)).exists(), ('owned process not cleaned', pid)
for name in ('stdout', 'stderr'):
    path = Path(record[name + '_path'])
    content = path.read_bytes()
    assert b'leader.pid' in content and b'descendant.pid' in content
    assert hashlib.sha256(content).hexdigest() == record[name + '_sha256']
# Launch exceptions also retain exact argv, timestamps and empty output files.
missing = [str(OUT / 'this-executable-does-not-exist'), 'retained argument']
try:
    runner.run(missing, timeout=2)
except FileNotFoundError:
    pass
else:
    raise AssertionError('controlled launch exception was not propagated')
record = json.loads((OUT / 'commands.json').read_text())[1]
assert record['arguments'] == missing and record['outcome'] == 'exception'
assert record['exception']['type'] == 'FileNotFoundError'
assert record['timeout_seconds'] == 2 and not record['timeout']
assert record['pid'] is None and record['returncode'] is None
assert record['cleanup']['complete'] and record['cleanup']['status'] == 'no process launched'
assert Path(record['stdout_path']).read_bytes() == Path(record['stderr_path']).read_bytes() == b''
# The supervisor remains usable after both expected failures.
assert runner.run([sys.executable, '-c', 'print("supervisor recovered")']) == b'supervisor recovered\n'
assert [r['outcome'] for r in runner.commands] == ['timeout', 'exception', 'passed']
report = {
    'status': 'PASS supervisor evidence/cleanup checks',
    'scope': 'The first two command attempts deliberately fail and remain timeout/exception, not successful runtime cases.',
    'expected_failure_outcomes': ['timeout', 'exception'],
    'leader_pid': leader, 'descendant_pid': descendant, 'both_proc_entries_absent': True,
    'orphan_descendant_reaped': True, 'post_failure_recovery': True,
    'memory_limit_bytes': LIMIT, 'serial': True,
    'local_prctl_header_sha256': hashlib.sha256(Path('/usr/include/linux/prctl.h').read_bytes()).hexdigest(),
    'sources': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in
                [Path(__file__), ROOT/'tests/gcc/measured_runtime_runner.py', ROOT/'tests/gcc/measured-runtime-timeout-child.py']},
}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS supervisor only: retained timeout/launch-exception attempts, killed and reaped owned descendant, subsequent command passed')
print(OUT / 'report.json')
