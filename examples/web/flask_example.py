# Flask import example for PyAOT
# This demonstrates that PyAOT can parse Flask's complex Python syntax

from flask import Flask, request, jsonify

# Create Flask app
app = Flask(__name__)

# Simple route
@app.route('/')
def hello():
    return "Hello from PyAOT-compiled Flask!"

# Route with parameters
@app.route('/greet/<name>')
def greet(name):
    return f"Hello, {name}!"

# JSON API endpoint
@app.route('/api/data')
def get_data():
    data = {
        "status": "success",
        "message": "PyAOT Flask API working",
        "items": [1, 2, 3, 4, 5]
    }
    return jsonify(data)

if __name__ == "__main__":
    print("Flask app routes:")
    print("  / - Hello world")
    print("  /greet/<name> - Personalized greeting")
    print("  /api/data - JSON API endpoint")
    print("\nTo run: flask run --app flask_example")
