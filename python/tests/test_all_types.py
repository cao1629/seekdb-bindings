import os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(os.path.dirname(HERE), "build")
sys.path.insert(0, BUILD)
import pylibseekdb as seekdb

db_dir = os.path.join(HERE, "seekdb.db")
shutil.rmtree(db_dir, ignore_errors=True)
os.makedirs(db_dir)
seekdb.open(db_dir=db_dir)
conn = seekdb.connect(database="test", autocommit=True)
cur = conn.cursor()
cur.execute("DROP TABLE IF EXISTS t")
cur.execute("""CREATE TABLE t (
    i  BIGINT,
    u  BIGINT UNSIGNED,
    f  DOUBLE,
    d  DECIMAL(10,2),
    dt DATE,
    ts TIMESTAMP NULL,
    v  VARCHAR(32),
    n  INT
)""")
cur.execute("""INSERT INTO t VALUES
    (-42, 18446744073709551000, 3.14, 99.95, '2026-01-15', '2026-05-11 10:00:00', 'hello', NULL)
""")
n = cur.execute("SELECT i, u, f, d, dt, ts, v, n FROM t")
print(f"row count: {n}")
for row in cur.fetchall():
    print(f"row: {row}")
    for i, val in enumerate(row):
        print(f"  col[{i}] = {val!r}  (type={type(val).__name__})")
print("OK")
