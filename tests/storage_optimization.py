"""Verify lossless migration of legacy archives and shared-image deletion."""
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

binary = sys.argv[1]
with tempfile.TemporaryDirectory(prefix="litt-storage-test-") as directory:
    root = Path(directory)
    env = dict(os.environ, LITT_HOME=directory)

    def run(*args):
        result = subprocess.run([binary, *args], env=env, check=True,
                                capture_output=True, text=True, timeout=15)
        return json.loads(result.stdout)

    # Create real OCR records, then reproduce v1's independent image storage.
    run("stats")
    with sqlite3.connect(root / "archive.sqlite") as db:
        db.execute("INSERT INTO settings(key,value) VALUES(?,?)", ("compressionMode", '"jpeg"'))
    fixture = str(Path(__file__).with_name("fixture.png"))
    run("import", fixture)
    run("import", fixture)
    images = sorted((root / "frames").glob("*.jpg"))
    data = images[1].read_bytes()
    images[1].unlink()
    images[1].write_bytes(data)
    with sqlite3.connect(root / "archive.sqlite") as db:
        db.executescript("DROP INDEX frames_image_hash; "
                         "ALTER TABLE frames DROP COLUMN image_hash; "
                         "ALTER TABLE frames DROP COLUMN storage_id; "
                         "PRAGMA user_version=1;")
        original = db.execute("SELECT * FROM frames ORDER BY id").fetchall()
    hashes = [hashlib.sha256(p.read_bytes()).hexdigest() for p in images]
    result = run("optimize")
    assert result["after"]["count"] == 2
    assert result["after"]["uniqueImages"] == 1
    assert result["after"]["deduplicatedBytes"] == len(data)
    assert images[0].samefile(images[1])
    assert hashes == [hashlib.sha256(p.read_bytes()).hexdigest() for p in images]
    with sqlite3.connect(root / "archive.sqlite") as db:
        migrated = db.execute("SELECT * FROM frames ORDER BY id").fetchall()
        assert [row[:len(original[0])] for row in migrated] == original
        assert db.execute("PRAGMA user_version").fetchone()[0] == 3
    assert run("optimize")["after"]["imageBytes"] == len(data)
    run("delete", images[0].stem)
    assert images[1].read_bytes() == data
    assert run("stats")["imageBytes"] == len(data)
    assert run("frame", images[1].stem)
    run("delete", images[1].stem)
    assert run("stats")["imageBytes"] == 0
    assert not list((root / "frames").glob("*.jpg"))
print("Legacy migration, hash/metadata preservation, idempotency and shared deletion passed")
