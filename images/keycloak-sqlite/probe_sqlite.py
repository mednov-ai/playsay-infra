"""Compare independently loaded SQLite builds without exposing real data."""
import ctypes
import json
import subprocess
import sys


def probe(path):
    lib = ctypes.CDLL(path)
    lib.sqlite3_libversion.restype = ctypes.c_char_p
    lib.sqlite3_compileoption_get.argtypes = [ctypes.c_int]
    lib.sqlite3_compileoption_get.restype = ctypes.c_char_p
    lib.sqlite3_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    lib.sqlite3_exec.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_void_p,
                                 ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
    lib.sqlite3_close.argtypes = [ctypes.c_void_p]
    lib.sqlite3_free.argtypes = [ctypes.c_void_p]
    options = []
    i = 0
    while True:
        option = lib.sqlite3_compileoption_get(i)
        if not option:
            break
        options.append(option.decode())
        i += 1
    db = ctypes.c_void_p()
    if lib.sqlite3_open(b':memory:', ctypes.byref(db)) != 0:
        raise RuntimeError('SQLite failed to open an in-memory database')

    def execute(sql):
        error = ctypes.c_void_p()
        rc = lib.sqlite3_exec(db, sql.encode(), None, None, ctypes.byref(error))
        message = ctypes.string_at(error).decode() if error.value else ''
        if error.value:
            lib.sqlite3_free(error)
        return rc, message

    basic, message = execute('CREATE TABLE t(x TEXT); INSERT INTO t VALUES (\'hello\'); SELECT x FROM t;')
    fts, fts_message = execute('CREATE VIRTUAL TABLE f USING fts5(content);')
    if lib.sqlite3_close(db) != 0 or basic != 0:
        raise RuntimeError(f'Basic SQLite operation failed: {message}')
    return {'version': lib.sqlite3_libversion().decode(), 'options': options,
            'ftsResult': fts, 'ftsMessage': fts_message}


if len(sys.argv) == 3 and sys.argv[1] == '--probe':
    print(json.dumps(probe(sys.argv[2]), sort_keys=True))
elif len(sys.argv) == 3:
    old = json.loads(subprocess.check_output([sys.executable, __file__, '--probe', sys.argv[1]], text=True))
    new = json.loads(subprocess.check_output([sys.executable, __file__, '--probe', sys.argv[2]], text=True))
    old_options = {x for x in old['options'] if not x.startswith('COMPILER=')}
    new_options = {x for x in new['options'] if not x.startswith('COMPILER=')}
    if old['version'] != new['version'] or old['ftsResult'] != 0 or new['ftsResult'] == 0:
        raise SystemExit('Unexpected version or FTS5 behavior')
    if 'no such module: fts5' not in new['ftsMessage']:
        raise SystemExit('The rebuilt library did not fail closed for FTS5')
    if old_options - new_options != {'ENABLE_FTS5'} or new_options - old_options:
        raise SystemExit('Compile options differ beyond FTS5: ' + json.dumps({
            'removed': sorted(old_options - new_options), 'added': sorted(new_options - old_options)}))
    print(json.dumps({'original': old, 'rebuilt': new, 'result': 'PASS'}, sort_keys=True))
else:
    raise SystemExit('usage: probe_sqlite.py OLD_LIBRARY NEW_LIBRARY')
