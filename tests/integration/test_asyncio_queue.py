"""Test asyncio.Queue implementation"""
import asyncio

# Test runner
passed = 0
failed = 0

def run(name):
    global passed
    passed += 1
    print(f"{name}: PASS")

# Test 1: Basic queue creation
def test_queue_creation():
    """Create queue with maxsize"""
    q = asyncio.Queue(10)
    assert q is not None
    run("queue_creation")

# Test 2: Queue size operations
def test_queue_size():
    """Test queue size methods"""
    q = asyncio.Queue(5)
    assert q.empty() == True
    assert q.full() == False
    assert q.qsize() == 0
    run("queue_size")

# Test 3: Non-blocking put/get
def test_queue_nowait():
    """Test non-blocking operations"""
    q = asyncio.Queue(3)

    # Put items
    q.put_nowait(1)
    q.put_nowait(2)
    q.put_nowait(3)

    assert q.full() == True
    assert q.qsize() == 3

    # Get items
    v1 = q.get_nowait()
    assert v1 == 1

    v2 = q.get_nowait()
    assert v2 == 2

    v3 = q.get_nowait()
    assert v3 == 3

    assert q.empty() == True
    run("queue_nowait")

# Run all tests
test_queue_creation()
test_queue_size()
test_queue_nowait()

print(f"\nPassed: {passed}/{passed + failed}")
