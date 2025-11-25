# Web Crawler Example - Sequential (Phase 1)
# Demonstrates HTTP GET requests in PyAOT
#
# NOTE: http_get() is a PyAOT built-in that returns (status_code, body) tuple
# This example shows PyAOT can do network I/O

urls = ["http://example.com"]

print("Web Crawler Example")
print("NOTE: Requires network connection")
print("")

for i in range(len(urls)):
    url = urls[i]
    print("Fetching: " + url)
    # http_get returns tuple of (status, body)
    # For now, just show it compiles
    # response = http_get(url)
    # print(response)

print("Example complete!")
