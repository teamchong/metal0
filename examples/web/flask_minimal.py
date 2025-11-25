# Minimal Flask-like class to test class methods and state
class SimpleApp:
    def __init__(self, routes):
        self.route_count = routes

    def add_route(self):
        self.route_count = self.route_count + 1

    def show_stats(self):
        print(self.route_count)

app = SimpleApp(0)
app.add_route()
app.add_route()
app.add_route()
app.show_stats()
