"""Flask app that demonstrates networking with requests.

Milestone 1: Prove ssl, socket, and HTTP work in pure Zig.
"""
from flask import Flask
import requests

app = Flask(__name__)


@app.route("/")
def hello():
    return "If you see this, PyAOT is fully compatible!"


if __name__ == "__main__":
    print("Flask + Requests demo")
    print("Testing requests.get() to prove networking works...")

    # Test requests.get with HTTPS - proves ssl/socket work
    resp = requests.get("https://httpbin.org/get")

    # Check if request succeeded
    if resp.ok:
        print("SUCCESS: HTTPS request completed!")
    else:
        print("ERROR: Request failed")

    print("Starting Flask server on default port...")
    app.run()
