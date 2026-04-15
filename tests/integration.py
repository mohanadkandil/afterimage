#!/usr/bin/env python3
"""Exercise the shipping binary, Apple Vision, SQLite and image export together."""
import json, os, pathlib, subprocess, tempfile, time, sys
binary = str(pathlib.Path(sys.argv[1]).resolve())
fixture = pathlib.Path(__file__).with_name('fixture.png')
with tempfile.TemporaryDirectory(prefix='litt-e2e-') as directory:
    env = dict(os.environ, LITT_HOME=directory)
    def run(*args, success=True):
        p = subprocess.run([binary, *map(str,args)], env=env, text=True, capture_output=True, timeout=60)
        assert (p.returncode == 0) == success, (args,p.stdout,p.stderr)
        return json.loads(p.stdout if success else p.stderr)
    started = time.monotonic()
    f = run('import', fixture)
    assert 'seahorse742' in f['text'].lower(), f['text']
    assert f['source'] == 'import' and len(f['boxes']) > 3
    for b in f['boxes']:
        assert 0 <= b['x'] <= 1 and 0 <= b['y'] <= 1 and b['w'] > 0 and b['h'] > 0
    assert run('search','seahorse742')[0]['id'] == f['id']
    assert run('search','seahorse742 nonexistentword') == []
    assert run('search','" OR *') == []
    assert run('list','--app','unknown.app') == []
    assert run('list','--from',f['time']+1) == []
    assert run('list','--offset',1) == []
    out = pathlib.Path(directory)/'export.jpg'
    run('export',f['id'],out)
    assert out.read_bytes().startswith(b'\xff\xd8')
    run('export',f['id'],out,success=False) # never silently overwrite from CLI
    run('import','/file-that-does-not-exist.png',success=False)
    assert run('stats')['count'] == 1
    run('delete',f['id'])
    assert run('search','seahorse742') == []
    assert run('stats')['count'] == 0
    run('frame',f['id'],success=False)
    assert list((pathlib.Path(directory)/'frames').iterdir()) == []
    print(json.dumps({'passed':True,'ocrBoxes':len(f['boxes']),'seconds':round(time.monotonic()-started,2)}))
