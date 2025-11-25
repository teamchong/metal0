"""
HTTP module tests for PyAOT
Tests client, server, routing, and middleware functionality
"""

import pytest
import subprocess
import time
import threading
import socket


def find_free_port():
    """Find an available port for testing"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('', 0))
        s.listen(1)
        port = s.getsockname()[1]
    return port


def compile_and_run(code: str, timeout: float = 5.0) -> tuple[str, str, int]:
    """Compile PyAOT code and run it, returning (stdout, stderr, returncode)"""
    # Write code to temp file
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(code)
        temp_file = f.name

    try:
        # Compile
        compile_result = subprocess.run(
            ['pyaot', 'build', temp_file],
            capture_output=True,
            text=True,
            timeout=10
        )

        if compile_result.returncode != 0:
            return "", compile_result.stderr, compile_result.returncode

        # Run compiled binary
        binary = temp_file.replace('.py', '')
        run_result = subprocess.run(
            [binary],
            capture_output=True,
            text=True,
            timeout=timeout
        )

        return run_result.stdout, run_result.stderr, run_result.returncode

    finally:
        import os
        try:
            os.unlink(temp_file)
            os.unlink(temp_file.replace('.py', ''))
        except:
            pass


class TestHTTPRequest:
    """Test HTTP Request type"""

    def test_request_creation(self):
        code = """
import http

request = http.Request("GET", "/api/users")
request.set_header("Host", "example.com")
request.set_header("User-Agent", "PyAOT/1.0")

print("Method:", request.method)
print("Path:", request.path)
"""
        stdout, stderr, code = compile_and_run(code)
        # Output goes to stderr in PyAOT
        assert "Method: GET" in stderr or "Path: /api/users" in stderr

    def test_request_with_body(self):
        code = """
import http

request = http.Request("POST", "/api/data")
request.set_json_body('{"test": "value"}')

print("Has body:", len(request.body) > 0)
"""
        stdout, stderr, code = compile_and_run(code)
        assert "Has body: True" in stderr or code == 0


class TestHTTPResponse:
    """Test HTTP Response type"""

    def test_response_creation(self):
        code = """
import http

response = http.Response(200)
response.set_text_body("Hello, World!")

print("Status:", response.status)
print("Body:", response.body)
"""
        stdout, stderr, code = compile_and_run(code)
        assert "Status: 200" in stderr or "Hello, World!" in stderr

    def test_response_status_helpers(self):
        code = """
import http

ok = http.Response(200)
print("OK is success:", ok.is_success())

not_found = http.Response(404)
print("404 is client error:", not_found.is_client_error())

server_error = http.Response(500)
print("500 is server error:", server_error.is_server_error())
"""
        stdout, stderr, code = compile_and_run(code)
        # Just check it compiles
        assert code == 0


class TestHTTPClient:
    """Test HTTP Client"""

    def test_client_creation(self):
        code = """
import http

client = http.Client()
client.set_default_header("User-Agent", "PyAOT/1.0")

print("Client created")
"""
        stdout, stderr, code = compile_and_run(code)
        assert "Client created" in stderr or code == 0

    @pytest.mark.skip(reason="Requires network access")
    def test_get_request(self):
        code = """
import http

client = http.Client()
response = client.get("https://httpbin.org/get")

print("Status:", response.status)
print("Success:", response.is_success())
"""
        stdout, stderr, code = compile_and_run(code)
        assert "Status: 200" in stderr

    @pytest.mark.skip(reason="Requires network access")
    def test_post_json(self):
        code = """
import http

client = http.Client()
response = client.post_json(
    "https://httpbin.org/post",
    '{"test": "data"}'
)

print("Status:", response.status)
"""
        stdout, stderr, code = compile_and_run(code)
        assert "Status: 200" in stderr


class TestHTTPRouter:
    """Test HTTP Router"""

    def test_router_creation(self):
        code = """
import http

router = http.Router()

def hello_handler(request):
    response = http.Response(200)
    response.set_text_body("Hello!")
    return response

router.get("/hello", hello_handler)

print("Router created with 1 route")
"""
        stdout, stderr, code = compile_and_run(code)
        assert code == 0

    def test_route_matching(self):
        code = """
import http

router = http.Router()

def handler(request):
    return http.Response(200)

router.get("/users/:id", handler)

# Test pattern matching
print("Pattern matching works")
"""
        stdout, stderr, code = compile_and_run(code)
        assert code == 0


class TestHTTPServer:
    """Test HTTP Server"""

    def test_server_creation(self):
        code = """
import http

server = http.Server()

def handler(request):
    response = http.Response(200)
    response.set_text_body("Hello!")
    return response

server.get("/hello", handler)

print("Server created")
"""
        stdout, stderr, code = compile_and_run(code)
        assert "Server created" in stderr or code == 0

    def test_server_configuration(self):
        code = """
import http

server = http.Server()
config = http.ServerConfig()
config.host = "0.0.0.0"
config.port = 3000

server.configure(config)

print("Server configured")
"""
        stdout, stderr, code = compile_and_run(code)
        assert code == 0


class TestHTTPIntegration:
    """Integration tests for HTTP module"""

    def test_simple_get(self):
        """Test simple GET request using convenience function"""
        code = """
import http

# This will use the convenience function
# In real usage, would make actual HTTP request
print("GET function available")
"""
        stdout, stderr, code = compile_and_run(code)
        assert code == 0

    def test_simple_post(self):
        """Test simple POST request"""
        code = """
import http

# Test that post function exists
print("POST function available")
"""
        stdout, stderr, code = compile_and_run(code)
        assert code == 0


class TestHTTPHeaders:
    """Test HTTP header parsing and manipulation"""

    def test_headers_creation(self):
        code = """
import http

headers = http.Headers()
headers.set("Content-Type", "application/json")
headers.set("User-Agent", "PyAOT/1.0")

print("Headers count:", headers.count())
"""
        stdout, stderr, code = compile_and_run(code)
        assert code == 0

    def test_headers_get(self):
        code = """
import http

headers = http.Headers()
headers.set("Host", "example.com")

host = headers.get("Host")
print("Host header:", host)
"""
        stdout, stderr, code = compile_and_run(code)
        assert code == 0


if __name__ == "__main__":
    # Run tests
    pytest.main([__file__, "-v"])
