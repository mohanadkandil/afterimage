"""Run native SwiftUI checks in disposable archives (requires a logged-in Mac)."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
binary = repo / 'build/Litt.app/Contents/MacOS/Litt'
for compact in (False, True):
    for populated in (False, True):
        with tempfile.TemporaryDirectory(prefix='litt-native-ui-') as directory:
            env = dict(os.environ, LITT_HOME=directory)
            env.pop('LITT_SMOKE_COMPACT', None)
            if compact:
                env['LITT_SMOKE_COMPACT'] = '1'
            if populated:
                for age in (20, 0):
                    subprocess.run([str(binary), 'import', str(repo / 'tests/fixture.png'), '--time', str(time.time() - age)], env=env, check=True, capture_output=True, timeout=30)
            output = str(Path(directory) / 'ui')
            subprocess.run([str(binary), '--ui-smoke', output], env=env, check=True, capture_output=True, timeout=30)
            result = json.loads(Path(output + '.json').read_text())
            assert result['passed'], result
            print('compact' if compact else 'regular', 'populated' if populated else 'empty', result)
