"""Linux-only serial test supervisor; never a production bootstrap input."""
from pathlib import Path
import ctypes
import datetime
import hashlib
import json
import os
import resource
import signal
import subprocess
import time


class Runner:
    def __init__(self, output, cwd, temporary, limit, timeout=300, cleanup_timeout=5):
        self.output = Path(output)
        self.cwd = Path(cwd)
        self.temporary = Path(temporary)
        self.limit = limit
        self.timeout = timeout
        self.cleanup_timeout = cleanup_timeout
        self.commands = []
        # Linux prctl.h: PR_SET_CHILD_SUBREAPER=36. Adopt and reap an owned
        # group's orphan descendants rather than leaving zombies to PID 1.
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(36, 1, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), 'PR_SET_CHILD_SUBREAPER failed')
        current = ctypes.c_int()
        if libc.prctl(37, ctypes.byref(current), 0, 0, 0) != 0 or current.value != 1:
            raise RuntimeError('PR_GET_CHILD_SUBREAPER did not confirm adoption')
        if resource.getrlimit(resource.RLIMIT_AS) != (limit, limit):
            raise RuntimeError('test address-space limit is not installed')

    def save(self):
        path = self.output / 'commands.json'
        temporary = self.output / '.commands.json.tmp'
        temporary.write_text(json.dumps(self.commands, indent=2) + '\n')
        os.replace(temporary, path)

    @staticmethod
    def members(group):
        found = []
        for path in Path('/proc').glob('[0-9]*/stat'):
            try:
                tail = path.read_text().rsplit(')', 1)[1].split()
                if int(tail[2]) == group:
                    found.append({'pid': int(path.parent.name), 'state': tail[0]})
            except (FileNotFoundError, ProcessLookupError):
                pass
        return found

    def cleanup(self, process):
        result = {'process_group': process.pid, 'signal': 'SIGKILL',
                  'signal_status': 'pending', 'reaped_descendants': [],
                  'members_before': None, 'remaining': None, 'errors': []}
        started = time.monotonic()

        def failure(stage, error):
            item = {'stage': stage, 'type': type(error).__name__, 'message': str(error)}
            if item not in result['errors']:
                result['errors'].append(item)

        try:
            result['members_before'] = self.members(process.pid)
        except BaseException as error:
            failure('initial group inspection', error)
        # Membership observation must never gate termination of the known
        # owned group. ESRCH is normal after a fully reaped successful command.
        try:
            os.killpg(process.pid, signal.SIGKILL)
            result['signal_status'] = 'sent to owned process group'
        except ProcessLookupError:
            result['signal_status'] = 'group already gone'
        except BaseException as error:
            failure('group termination', error)
        try:
            # Popen owns the leader; the orphan loop must not reap it.
            process.wait(timeout=self.cleanup_timeout)
        except BaseException as error:
            failure('leader wait', error)
        deadline = time.monotonic() + self.cleanup_timeout
        while True:
            no_group_children = False
            try:
                while True:
                    try:
                        pid, status = os.waitpid(-process.pid, os.WNOHANG)
                    except ChildProcessError:
                        no_group_children = True
                        break
                    if pid == 0:
                        break
                    result['reaped_descendants'].append({'pid': pid, 'wait_status': status})
            except BaseException as error:
                failure('descendant reaping', error)
            try:
                result['remaining'] = self.members(process.pid)
            except BaseException as error:
                failure('final group inspection', error)
                # Inspection failure cannot stop bounded orphan reaping. A
                # killed descendant may not be waitable on the first pass.
                result['remaining'] = None
            if ((result['remaining'] == [] or
                 (result['remaining'] is None and no_group_children))
                    or time.monotonic() >= deadline):
                break
            time.sleep(0.01)
        result['leader_returncode'] = process.returncode
        result['seconds'] = time.monotonic() - started
        result['complete'] = (not result['errors'] and result['remaining'] == []
                              and process.returncode is not None)
        return result

    def run(self, arguments, timeout=None):
        command = list(map(str, arguments))
        timeout = self.timeout if timeout is None else timeout
        index = len(self.commands)
        stdout_path = self.output / ('command-%02d.stdout' % index)
        stderr_path = self.output / ('command-%02d.stderr' % index)
        started = time.monotonic()
        record = {'arguments': command, 'cwd': str(self.cwd), 'timeout_seconds': timeout,
                  'memory_limit_bytes': self.limit, 'cleanup_timeout_seconds': self.cleanup_timeout,
                  'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'started_monotonic': started, 'finished_utc': None, 'seconds': None,
                  'stdout_path': str(stdout_path), 'stderr_path': str(stderr_path),
                  'pid': None, 'process_group': None, 'returncode': None,
                  'outcome': 'starting', 'timeout': False, 'exception': None,
                  'cleanup': {'complete': True, 'status': 'no process launched'}}
        self.commands.append(record)
        self.save()  # Retain the attempted argv even if launch itself fails.
        process = None
        caught = None
        try:
            with stdout_path.open('wb') as stdout, stderr_path.open('wb') as stderr:
                try:
                    process = subprocess.Popen(command, cwd=self.cwd, stdout=stdout, stderr=stderr,
                                               env=dict(os.environ, LC_ALL='C', TMPDIR=str(self.temporary)),
                                               start_new_session=True)
                    record.update(pid=process.pid, process_group=process.pid, outcome='running',
                                  cleanup={'complete': False, 'status': 'pending for launched process'})
                    self.save()
                    process.wait(timeout=timeout)
                except BaseException as error:
                    caught = error
                    record['timeout'] = isinstance(error, subprocess.TimeoutExpired)
                    record['exception'] = {'type': type(error).__name__, 'message': str(error)}
                finally:
                    if process is not None:
                        record['cleanup'] = self.cleanup(process)
                        record['returncode'] = process.returncode
        except BaseException as error:
            caught = error
            record['exception'] = {'type': type(error).__name__, 'message': str(error)}
        output = stdout_path.read_bytes() if stdout_path.exists() else b''
        errors = stderr_path.read_bytes() if stderr_path.exists() else b''
        record.update(finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      seconds=time.monotonic() - started,
                      stdout_sha256=hashlib.sha256(output).hexdigest(),
                      stderr_sha256=hashlib.sha256(errors).hexdigest(),
                      stdout_bytes=len(output), stderr_bytes=len(errors),
                      stderr=errors.decode(errors='replace'))
        if record['timeout']:
            record['outcome'] = 'timeout'
        elif caught is not None:
            record['outcome'] = 'exception'
        elif not record['cleanup']['complete']:
            record['outcome'] = 'cleanup failure'
        elif record['cleanup'].get('members_before'):
            record['outcome'] = 'descendants remained after leader exit'
        elif record['returncode'] != 0 or errors:
            record['outcome'] = 'command failure'
        else:
            record['outcome'] = 'passed'
        self.save()  # Final failure/cleanup evidence precedes every re-raise.
        if caught is not None:
            raise caught
        assert record['outcome'] == 'passed', record
        return output
