# seekdb-bindings

C client library, CLI, and Python bindings for [seekdb](https://github.com/oceanbase/oceanbase).

## Clone

The repo uses git submodules (mariadb-connector-c, googletest, openssl). Clone with `--recursive` so they come along:

```sh
git clone --recursive https://github.com/cao1629/seekdb-bindings.git
cd seekdb-bindings
```

If you already cloned without `--recursive`, init the submodules after the fact:

```sh
git submodule update --init --recursive
```

## Build libseekdb_client

```sh
mkdir build && cd build
cmake -DSEEKDB_BIN=/path/to/seekdb ..
cmake --build .
```

### Enable / disable debug logs
Enable:

```sh
cmake -DSEEKDB_BIN=... -DSEEKDB_ENABLE_LOG=ON ..
cmake --build .
```

Disable (default):

```sh
cmake -DSEEKDB_BIN=... ..
cmake --build .
```


## Use seekdb_cli

Interactive SQL client, same shape as `mysql`/`mariadb`:

```sh
./build/seekdb_cli [db_dir]
```

`db_dir` is optional — defaults to `./seekdb.db` (created if missing). The seekdb server binary is auto-discovered next to `libseekdb_client.so` (which is also next to `seekdb_cli`).


## Python bindings

Build the `pylibseekdb` extension. Requires `pybind11` for the Python interpreter you build against:

```sh
python3 -m pip install --user pybind11
```

Then:

```sh
cd python
mkdir build && cd build
cmake ..
cmake --build .
```

`SEEKDB_CLIENT_LIB_DIR` defaults to `../build` (the top-level build dir). Override with `-DSEEKDB_CLIENT_LIB_DIR=<path>` if your layout differs.


### Run the tests

Point `PYTHONPATH` at the python build dir so `import pylibseekdb` resolves:

```sh
export PYTHONPATH=$PWD/python/build
python3 python/tests/test.py           
python3 python/tests/test_all_types.py  
python3 python/tests/seekdb_test.py   
```
