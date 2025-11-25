# Complete Flask-like web framework for PyAOT
# Demonstrates core Flask concepts

class Flask:
    def __init__(self):
        self.route_count = 0
        self.request_count = 0

    def add_route(self, path_id):
        # Register a route
        self.route_count = self.route_count + path_id

    def handle_request(self, path_id):
        # Handle HTTP request
        self.request_count = self.request_count + 1
        return 200 + path_id

    def get_stats(self):
        return self.route_count

    def get_request_count(self):
        return self.request_count

# Create Flask app
app = Flask()

# Register routes
app.add_route(1)
app.add_route(1)
app.add_route(1)

print(app.get_stats())  # 3

# Simulate HTTP requests
status1 = app.handle_request(1)
print(status1)  # 201

status2 = app.handle_request(2)
print(status2)  # 202

status3 = app.handle_request(3)
print(status3)  # 203

print(app.get_request_count())  # 3
