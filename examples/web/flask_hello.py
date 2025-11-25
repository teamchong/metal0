# Flask-like demonstration - shows what PyAOT can compile today
# This demonstrates: classes, decorators, method calls, dict storage

class Flask:
    def __init__(self, name):
        self.name = name
        self.routes = {}

    def add_route(self, path, handler):
        self.routes[path] = handler
        print("Registered route: " + path)

    def show_routes(self):
        print("Flask app '" + self.name + "' routes:")
        for path in self.routes:
            handler = self.routes[path]
            result = handler()
            print("  " + path + " -> " + result)

# Route handlers
def index():
    return "Hello from PyAOT + Flask!"

def about():
    return "AOT-compiled Python web server"

def api():
    return "JSON response here"

# Create app and register routes
app = Flask("pyaot_demo")
app.add_route("/", index)
app.add_route("/about", about)
app.add_route("/api/status", api)

# Show registered routes
app.show_routes()

print("\nSuccess! Flask-style routing works in PyAOT")
