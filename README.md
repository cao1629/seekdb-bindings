# seekdb-bindings

C client library (`libseekdb_client.so`), CLI tool (`seekdb_cli`), and Python bindings (`seekdb_pyclient`) for the [seekdb](https://github.com/oceanbase/oceanbase) server.

## Build

```sh
git clone --recursive https://github.com/cao1629/seekdb-bindings.git
cd seekdb-bindings
cmake -B build
cmake --build build -j
```

If you didn't clone with `--recursive`:

```sh
git submodule update --init --recursive
```

This produces:

- `build/libseekdb_client.so` — the client library
- `build/seekdb_cli` — interactive SQL CLI
- `build/test_one_client_process`, `build/test_two_clients_processes`, `build/test_two_clients_threads` — gtest binaries

## seekdb_cli

Interactive SQL client, same shape as `mysql`/`mariadb`.

```sh
./build/seekdb_cli <seekdb_daemon_bin> <db_dir>
```

- `<seekdb_daemon_bin>` — path to the seekdb server binary (e.g. `~/seekdb/build_debug/src/observer/seekdb`)
- `<db_dir>` — directory for this seekdb instance's data. Created if missing. The CLI spawns a server here on first connect.

Example session:

```
$ ./build/seekdb_cli ~/seekdb/build_debug/src/observer/seekdb /tmp/mydb
Welcome to the SeekDB monitor.
Type 'help' for help. Terminate each statement with ';'.

seekdb> CREATE DATABASE test;
Query OK

seekdb> CREATE TABLE test.t1 (a INT, b VARCHAR(32));
Query OK

seekdb> INSERT INTO test.t1 VALUES (1, 'hello'), (2, 'world');
Query OK

seekdb> SELECT * FROM test.t1;
+---+-------+
| a | b     |
+---+-------+
| 1 | hello |
| 2 | world |
+---+-------+
2 rows in set

seekdb> quit
```

Terminate statements with `;`. Type `quit` or `exit` to leave (or Ctrl-D).

## Python bindings

Build the extension (requires `pybind11` for the chosen Python):

```sh
pip install --user pybind11
cd python
cmake -B build \
  -DSEEKDB_CLIENT_DIR=$PWD/.. \
  -DSEEKDB_CLIENT_LIB_DIR=$PWD/../build
cmake --build build -j
```

This produces `python/build/seekdb_pyclient.cpython-*.so`.

### Run the bundled test

```sh
export SEEKDB_BIN=~/seekdb/build_debug/src/observer/seekdb   # seekdb server binary
export SEEKDB_DB=/tmp/seekdb_python_test_data                 # optional, default shown
python3 python/tests/test.py
```

Expected output:

```
sc.open(db_dir=/tmp/seekdb_python_test_data)
sc.connect(database='test', autocommit=True)
cur.execute("SELECT 1")
  row count returned: 1
cur.fetchall():
  (1,)
OK
```

### Usage from your own code

```python
import seekdb_pyclient as sc

sc.open(db_dir="/tmp/mydb")
conn = sc.connect(database="test", autocommit=True)
cur = conn.cursor()
cur.execute("SELECT 1")
for row in cur.fetchall():
    print(row)
```

Set `SEEKDB_BIN` to the seekdb server binary path before importing — `sc.open` spawns the server.
