import os
import signal
import subprocess
import sys

binary = sys.argv[1]
for scenario in ['success', 'disconnected', 'service-failed', 'registry-failed', 'no-watches', 'missing-name', 'invalid-level']:
    result = subprocess.run([binary, 'test-phone'], env={**os.environ, 'WATCH_SCENARIO': scenario}, capture_output=True, text=True, timeout=16)
    if scenario == 'success':
        assert result.returncode == 0
        assert 'DeviceName: Test Watch' in result.stdout
        assert 'Checking watch watch-one-full-id' in result.stdout
        assert 'BatteryCurrentCapacity: 42' in result.stdout
        assert 'BatteryIsCharging: true' in result.stdout
    else:
        assert not result.stdout, (scenario, result.stdout)
        assert result.returncode == (0 if scenario == 'no-watches' else 1), (scenario, result.returncode)
    assert 'AddressSanitizer' not in result.stderr, result.stderr
    print('PASS:', scenario)
for sig in [signal.SIGTERM, signal.SIGINT, signal.SIGALRM]:
    child = subprocess.Popen([binary, 'test-phone'], env={**os.environ, 'WATCH_SCENARIO': 'blocked'}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        import select
        assert select.select([child.stderr], [], [], 5)[0], 'No readiness event'
        assert child.stderr.readline() == 'ready\n'
        if sig != signal.SIGALRM:
            child.send_signal(sig)
        out, err = child.communicate(timeout=16 if sig == signal.SIGALRM else 2)
        assert child.returncode == -sig and not out and not err
        print('PASS: blocked lookup terminated by', sig.name)
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
