# Simplified Flask-like framework (without decorators)
class SimpleFlask:
    def __init__(self, name):
        self.name = name
        self.routes = {}

    def add_route(self, path, handler):
        self.routes[path] = handler

    def run(self):
        print("Registered routes:")
        for path in self.routes:
            handler = self.routes[path]
            print("  " + path)
            result = handler()
            print("    Returns: " + result)

def index():
    return "Home page"

def about():
    return "About page"

app = SimpleFlask("__main__")
app.add_route("/", index)
app.add_route("/about", about)
app.run()
