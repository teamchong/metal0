# Math module tests (from Codon stdlib)
import math

# Test runner
passed = 0

def run(name):
    global passed
    passed += 1
    print(f"{name}: PASS")


def close(a: float, b: float, epsilon: float = 1e-7):
    """Helper to compare floats with epsilon tolerance"""
    return abs(a - b) <= epsilon


def test_math_constants():
    """Test math module constants"""
    assert math.pi > 3.14
    assert math.pi < 3.15
    assert math.e > 2.71
    assert math.e < 2.72


def test_math_ceil():
    """Test math.ceil() function"""
    assert math.ceil(3.3) == 4
    assert math.ceil(0.5) == 1
    assert math.ceil(1.0) == 1
    assert math.ceil(1.5) == 2
    assert math.ceil(-0.5) == 0
    assert math.ceil(-1.0) == -1
    assert math.ceil(-1.5) == -1


def test_math_floor():
    """Test math.floor() function"""
    assert math.floor(3.3) == 3
    assert math.floor(0.5) == 0
    assert math.floor(1.0) == 1
    assert math.floor(1.5) == 1
    assert math.floor(-0.5) == -1
    assert math.floor(-1.0) == -1
    assert math.floor(-1.5) == -2


def test_math_fabs():
    """Test math.fabs() function"""
    assert math.fabs(-1.0) == 1.0
    assert math.fabs(0.0) == 0.0
    assert math.fabs(1.0) == 1.0


def test_math_fmod():
    """Test math.fmod() function"""
    assert math.fmod(10.0, 1.0) == 0.0
    assert math.fmod(10.0, 0.5) == 0.0
    assert math.fmod(10.0, 1.5) == 1.0
    assert math.fmod(-10.0, 1.0) == -0.0
    assert math.fmod(-10.0, 0.5) == -0.0
    assert math.fmod(-10.0, 1.5) == -1.0


def test_math_exp():
    """Test math.exp() function"""
    assert math.exp(0.0) == 1.0
    assert close(math.exp(-1.0), 1.0 / math.e)
    assert close(math.exp(1.0), math.e)


def test_math_log():
    """Test math.log() function"""
    assert close(math.log(1.0 / math.e), -1.0)
    assert math.log(1.0) == 0.0
    assert close(math.log(math.e), 1.0)


def test_math_log2():
    """Test math.log2() function"""
    assert math.log2(1.0) == 0.0
    assert math.log2(2.0) == 1.0
    assert math.log2(4.0) == 2.0
    assert math.log2(8.0) == 3.0


def test_math_log10():
    """Test math.log10() function"""
    assert close(math.log10(0.1), -1.0)
    assert math.log10(1.0) == 0.0
    assert close(math.log10(10.0), 1.0)
    assert close(math.log10(10000.0), 4.0)


def test_math_sqrt():
    """Test math.sqrt() function"""
    assert math.sqrt(4.0) == 2.0
    assert math.sqrt(9.0) == 3.0
    assert math.sqrt(16.0) == 4.0
    assert math.sqrt(0.0) == 0.0
    assert close(math.sqrt(2.0), 1.414213562)


def test_math_pow():
    """Test math.pow() function"""
    assert math.pow(2.0, 3.0) == 8.0
    assert math.pow(3.0, 2.0) == 9.0
    assert math.pow(5.0, 0.0) == 1.0
    assert math.pow(2.0, 10.0) == 1024.0


def test_math_degrees():
    """Test math.degrees() function"""
    assert close(math.degrees(math.pi), 180.0)
    assert close(math.degrees(math.pi / 2), 90.0)
    assert close(math.degrees(-math.pi / 4), -45.0)
    assert math.degrees(0.0) == 0.0


def test_math_radians():
    """Test math.radians() function"""
    assert close(math.radians(180.0), math.pi)
    assert close(math.radians(90.0), math.pi / 2)
    assert close(math.radians(-45.0), -math.pi / 4)
    assert math.radians(0.0) == 0.0


def test_math_sin():
    """Test math.sin() function"""
    assert math.sin(0.0) == 0.0
    assert close(math.sin(math.pi / 2), 1.0)
    assert close(math.sin(math.pi), 0.0, 1e-6)


def test_math_cos():
    """Test math.cos() function"""
    assert math.cos(0.0) == 1.0
    assert close(math.cos(math.pi / 2), 0.0, 1e-6)
    assert close(math.cos(math.pi), -1.0)


def test_math_tan():
    """Test math.tan() function"""
    assert math.tan(0.0) == 0.0
    assert close(math.tan(math.pi / 4), 1.0)


def test_math_isnan():
    """Test math.isnan() function"""
    assert math.isnan(float('nan')) == True
    assert math.isnan(4.0) == False
    assert math.isnan(0.0) == False


def test_math_isinf():
    """Test math.isinf() function"""
    assert math.isinf(float('inf')) == True
    assert math.isinf(float('-inf')) == True
    assert math.isinf(7.0) == False


def test_math_isfinite():
    """Test math.isfinite() function"""
    assert math.isfinite(1.4) == True
    assert math.isfinite(0.0) == True
    assert math.isfinite(float('nan')) == False
    assert math.isfinite(float('inf')) == False
    assert math.isfinite(float('-inf')) == False


if __name__ == "__main__":
    test_math_constants(); run("test_math_constants")
    test_math_ceil(); run("test_math_ceil")
    test_math_floor(); run("test_math_floor")
    test_math_fabs(); run("test_math_fabs")
    test_math_fmod(); run("test_math_fmod")
    test_math_exp(); run("test_math_exp")
    test_math_log(); run("test_math_log")
    test_math_log2(); run("test_math_log2")
    test_math_log10(); run("test_math_log10")
    test_math_sqrt(); run("test_math_sqrt")
    test_math_pow(); run("test_math_pow")
    test_math_degrees(); run("test_math_degrees")
    test_math_radians(); run("test_math_radians")
    test_math_sin(); run("test_math_sin")
    test_math_cos(); run("test_math_cos")
    test_math_tan(); run("test_math_tan")
    test_math_isnan(); run("test_math_isnan")
    test_math_isinf(); run("test_math_isinf")
    test_math_isfinite(); run("test_math_isfinite")

    print(f"\nAll {passed} math tests passed!")
