#!/usr/bin/env python3
"""Flask Hello World - PyAOT Go Killer Demo"""

from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello, World from PyAOT Flask!"

@app.route("/api/status")
def status():
    return {"status": "ok", "server": "PyAOT Flask"}

if __name__ == "__main__":
    print("Starting PyAOT Flask server...")
    app.run(host="127.0.0.1", port=5000)
