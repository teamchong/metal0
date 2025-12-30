#!/usr/bin/env python3
"""
Development server with Cross-Origin-Isolation headers for SharedArrayBuffer support.

Usage:
    python server.py [port]

The server adds the following headers required for SharedArrayBuffer:
    - Cross-Origin-Opener-Policy: same-origin
    - Cross-Origin-Embedder-Policy: require-corp

These enable:
    - SharedArrayBuffer for zero-copy data sharing between workers
    - Atomics for synchronization primitives
    - High-resolution timing (performance.now())
"""

import http.server
import socketserver
import sys
import os

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 3000

class CORSRequestHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler with CORS and Cross-Origin-Isolation headers."""

    def end_headers(self):
        # Cross-Origin-Isolation headers for SharedArrayBuffer
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')

        # CORS headers for local development
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Range, Content-Type')
        self.send_header('Access-Control-Expose-Headers', 'Content-Length, Content-Range')

        # Cache control for development
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')

        super().end_headers()

    def do_OPTIONS(self):
        """Handle CORS preflight requests."""
        self.send_response(200)
        self.end_headers()

    def guess_type(self, path):
        """Return correct MIME type for WASM and JS modules."""
        if path.endswith('.wasm'):
            return 'application/wasm'
        if path.endswith('.js'):
            return 'application/javascript'
        if path.endswith('.mjs'):
            return 'application/javascript'
        return super().guess_type(path)

    def log_message(self, format, *args):
        """Custom log format with color coding."""
        method = args[0].split()[0] if args else ''
        status = args[1] if len(args) > 1 else ''

        # Color codes
        green = '\033[92m'
        yellow = '\033[93m'
        red = '\033[91m'
        reset = '\033[0m'

        if status.startswith('2'):
            color = green
        elif status.startswith('3'):
            color = yellow
        else:
            color = red

        print(f"{color}{method}{reset} {args[0]} - {status}")


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)) or '.')

    with socketserver.TCPServer(("", PORT), CORSRequestHandler) as httpd:
        print(f"""
╔════════════════════════════════════════════════════════════════╗
║  LanceQL Development Server                                    ║
╠════════════════════════════════════════════════════════════════╣
║  URL: http://localhost:{PORT:<5}                                  ║
║                                                                ║
║  Features enabled:                                             ║
║    ✓ Cross-Origin-Isolation (SharedArrayBuffer)               ║
║    ✓ CORS for remote data fetching                            ║
║    ✓ Proper MIME types for WASM/JS modules                    ║
║                                                                ║
║  Press Ctrl+C to stop                                          ║
╚════════════════════════════════════════════════════════════════╝
        """)

        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")


if __name__ == '__main__':
    main()
