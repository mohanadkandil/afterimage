"""Exercise real HEVC publication, restart, export, deletion and orphan recovery."""
import json
import os
from pathlib import Path
import sqlite3
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib

binary = sys.argv[1]

def png(path, frame):
    width, height = 640, 360
    pixels = bytearray()
    for y in range(height):
        pixels.append(0)
        for x in range(width):
            moving = frame * 12 <= x < frame * 12 + 35 and 100 <= y < 180
            pixels.extend((230, 70, 80) if moving else (x % 180 + 30, y % 180 + 30, 60))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))

with tempfile.TemporaryDirectory(prefix='litt-video-') as directory:
    base = Path(directory)
    root = base / 'archive'
    env = dict(os.environ, LITT_HOME=str(root))
    def run(*args):
        result = subprocess.run([binary, *map(str, args)], env=env, check=True,
                                capture_output=True, text=True, timeout=30)
        return json.loads(result.stdout)
    for i in range(30):
        fixture = base / 'input.png'
        png(fixture, i)
        run('import', fixture, '--time', time.time() - 60 + i)
    stats = run('stats')
    assert stats['count'] == 30 and stats['segments'] == 1, stats
    assert stats['videoBytes'] > 0 and stats['stillBytes'] == 0, stats
    assert not list((root / 'frames').glob('*.jpg'))
    with sqlite3.connect(root / 'archive.sqlite') as db:
        rows = db.execute('SELECT id,segment_index FROM frames ORDER BY id').fetchall()
    assert [r[1] for r in rows] == list(range(30))
    # Whole-chunk retention must delete media outright, without decoding survivors.
    expired = base / 'expired'
    shutil.copytree(root, expired)
    with sqlite3.connect(expired / 'archive.sqlite') as db:
        db.execute('UPDATE frames SET time=?', (time.time() - 3 * 86400,))
    env['LITT_HOME'] = str(expired)
    assert run('prune', 1)['deleted'] == 30
    assert run('stats')['count'] == 0
    assert not list((expired / 'segments').iterdir())
    env['LITT_HOME'] = str(root)
    old_segment = next((root / 'segments').glob('*.mp4'))
    export = base / 'survivor.png'
    run('export', rows[-1][0], export)
    expected = export.read_bytes()
    assert expected.startswith(b'\x89PNG')
    assert struct.unpack('>II', expected[16:24]) == (640, 360)
    orphan = root / 'segments' / 'abandoned.partial.mp4'
    orphan.write_bytes(b'incomplete')
    assert run('compact')['packedFrames'] == 0
    assert not orphan.exists()
    run('delete', rows[0][0])
    assert not old_segment.exists(), 'Deleted pixels must not remain inside an old video chunk'
    assert run('stats')['count'] == 29
    assert not (root / 'cache' / f'{rows[0][0]}.png').exists()
    export.unlink()
    run('export', rows[-1][0], export)
    assert export.read_bytes() == expected, 'Survivor pixels changed during deletion'
    assert run('compact')['packedFrames'] == 0, 'Survivors must not be repeatedly lossy-encoded'
    run('prune', 1)  # No current frames should be pruned.
    assert run('stats')['count'] == 29
print('HEVC automatic batching, frame indices, PNG export, restart, partial deletion and orphan recovery passed')
