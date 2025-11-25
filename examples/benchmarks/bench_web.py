"""
HTTP Server benchmark placeholder

To run actual benchmark:
1. Install aiohttp: pip install aiohttp
2. Uncomment code below
3. Run: pyaot examples/bench_web.py
4. Test: wrk -t4 -c100 -d10s http://localhost:8080/json
"""

print("HTTP benchmark requires aiohttp")
print("Install: pip install aiohttp")
print("")
print("Then run:")
print("  pyaot examples/bench_web.py &")
print("  wrk -t4 -c100 -d10s http://localhost:8080/json")

# Uncomment when aiohttp is available:
# from aiohttp import web
#
# async def json_handler(request):
#     return web.json_response({"message": "Hello, World!"})
#
# app = web.Application()
# app.router.add_get('/json', json_handler)
# web.run_app(app, port=8080)
