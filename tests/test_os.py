# Test os module
import os

# Test getcwd
cwd = os.getcwd()
print("Current dir:", cwd)

# Test os.path functions
test_path = "/Users/steven_chong/test/file.txt"
dirname = os.path.dirname(test_path)
print("dirname:", dirname)

basename = os.path.basename(test_path)
print("basename:", basename)

joined = os.path.join("/Users", "steven_chong", "test")
print("joined:", joined)

exists = os.path.exists(".")
print("exists .:", exists)
