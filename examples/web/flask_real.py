# Try to import and use real Flask
# This will show what Python features are missing

# Simplified Flask-style app without imports
# (once we can compile Flask library, this will work with: from flask import Flask)

class Flask:
    def __init__(self, name):
        self.name = name
        self.routes = {}

    def route(self, path):
        def decorator(func):
            self.routes[path] = func
            return func
        return decorator

    def run(self):
        print("Routes:")
        for path in self.routes:
            print(path)

app = Flask("test")

# This SHOULD work with decorator syntax:
# @app.route('/')
# def index():
#     return "Hello"

# For now, manual registration:
def index():
    return "Hello"

def about():
    return "About"

app.routes["/"] = index
app.routes["/about"] = about

app.run()
