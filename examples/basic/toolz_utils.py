def raises(err, lamda):
    try:
        lamda()
        return False
    except err:
        return True

# Test it
def division_test():
    result = raises(ZeroDivisionError, lambda: 1 / 0)
    assert result == True
    print("Test passed!")

division_test()
