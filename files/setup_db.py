from db import get_conn, init_db

conn = get_conn()
init_db(conn)
print("Database created: financegotchi.db")