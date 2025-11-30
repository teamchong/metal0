# Test BigInt integration
# This tests int() with large values that exceed i64/i128 range

def test_bigint_from_large_float():
    # 1e100 exceeds i64 and i128 range
    x = int(1e100)
    print(x)

if __name__ == "__main__":
    test_bigint_from_large_float()
    print("All BigInt tests passed!")
