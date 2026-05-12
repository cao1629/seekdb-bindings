import os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(os.path.dirname(HERE), "build")
sys.path.insert(0, BUILD)
import pylibseekdb as seekdb

db_dir = os.path.join(HERE, "seekdb.db")
shutil.rmtree(db_dir, ignore_errors=True)
os.makedirs(db_dir)
seekdb.open(db_dir=db_dir)
conn = seekdb.connect("test")
cursor = conn.cursor()
cursor.execute('drop table if exists doc_table')
cursor.execute('''create table doc_table(c1 int,
                                         vector vector(3),
                                         query varchar(255),
                                         content varchar(255),
                                         vector index idx1(vector) with
                                              (distance=l2, type=hnsw, lib=vsag),
                                         fulltext idx2(query),
                                         fulltext idx3(content))''')

sql = '''insert into doc_table values
						(1, '[1,2,3]', "hello world", "oceanbase Elasticsearch database"),
						(2, '[1,2,1]', "hello world, what is your name", "oceanbase mysql database"),
						(3, '[1,1,1]', "hello world, how are you", "oceanbase oracle database"),
						(4, '[1,3,1]', "real world, where are you from", "postgres oracle database"),
						(5, '[1,3,2]', "real world, how old are you", "redis oracle database"),
						(6, '[2,1,1]', "hello world, where are you from", "starrocks oceanbase database")'''
cursor.execute(sql)
conn.commit()

sql = '''
    SET @parm = '{
      "query": {
        "bool": {
          "should": [
            {"match": {"query": "hi hello"}},
            {"match": { "content": "oceanbase mysql" }}
          ]
        }
      },
       "knn" : {
          "field": "vector",
          "k": 5,
          "query_vector": [1,2,3]
      },
      "_source" : ["query", "content", "_keyword_score", "_semantic_score"]
    }'
    '''
cursor.execute(sql)
conn.commit()
sql = '''SELECT json_pretty(DBMS_HYBRID_SEARCH.SEARCH('doc_table', @parm))'''
cursor.execute(sql)
print(cursor.fetchall())