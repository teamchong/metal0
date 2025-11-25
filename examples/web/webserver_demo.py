# Simple web server simulation (without HTTP, just showing routing logic)
class WebServer:
    def __init__(self):
        self.route_count = 0
        self.request_count = 0

    def add_route(self):
        self.route_count = self.route_count + 1

    def handle_request(self):
        self.request_count = self.request_count + 1
        return self.request_count

    def stats(self):
        print(self.route_count)
        print(self.request_count)

# Create server
server = WebServer()

# Register routes (simulated)
server.add_route()  # GET /
server.add_route()  # GET /about
server.add_route()  # POST /api/data

# Simulate requests
r1 = server.handle_request()
print(r1)
r2 = server.handle_request()
print(r2)
r3 = server.handle_request()
print(r3)

# Show stats
server.stats()
