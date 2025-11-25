"""Math module that uses utils"""
import test_utils

def compute(x: int) -> int:
    doubled = test_utils.double(x)
    tripled = test_utils.triple(x)
    return doubled + tripled
