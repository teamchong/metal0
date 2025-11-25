import sys

# Test comptime platform detection
if sys.platform == "darwin":
    print("Running on macOS")
elif sys.platform == "linux":
    print("Running on Linux")
elif sys.platform == "win32":
    print("Running on Windows")
else:
    print("Unknown platform")

# Test version_info access
print(sys.version_info.major)
print(sys.version_info.minor)
