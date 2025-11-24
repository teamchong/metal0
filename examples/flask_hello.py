from flask import Flask

app = Flask("hello")

@app.route("/")
def hello():
    return "Hello, World!"

# Note: app.run() with kwargs not yet supported
# if __name__ == "__main__":
#     app.run(host="0.0.0.0", port=8080)
