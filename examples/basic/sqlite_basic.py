import sqlite3

conn = sqlite3.connect("test.db")
conn.execute("CREATE TABLE users (id INTEGER, name TEXT)")
conn.execute("INSERT INTO users VALUES (1, 'Alice')")
conn.close()
print("Database operations successful")
