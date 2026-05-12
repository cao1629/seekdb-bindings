import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(os.path.dirname(HERE), "build")
sys.path.insert(0, BUILD)

import pylibseekdb as seekdb

db_dir = os.path.join(HERE, "seekdb.db")
shutil.rmtree(db_dir, ignore_errors=True)
os.makedirs(db_dir)

print(f"seekdb.open(db_dir={db_dir})")
seekdb.open(db_dir=db_dir)

print("seekdb.connect(database='test', autocommit=True)")
conn = seekdb.connect(database="test", autocommit=True)

cur = conn.cursor()
print('cur.execute("SELECT 1")')
n = cur.execute("SELECT 1")
print(f"  row count returned: {n}")

print("cur.fetchall():")
for row in cur.fetchall():
    print(f"  {row}")

print("OK")
