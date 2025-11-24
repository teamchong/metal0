# String method tests (from Codon stdlib)

# Test runner
passed = 0
failed = 0

def run(name):
    global passed, failed
    passed += 1
    print(f"{name}: PASS")

def test_isdigit():
    """Test str.isdigit() method"""
    assert "0".isdigit() == True
    assert "".isdigit() == False
    assert "a".isdigit() == False
    assert "2829357".isdigit() == True
    assert "kshfkjhe".isdigit() == False
    assert "9735g385497".isdigit() == False


def test_islower():
    """Test str.islower() method"""
    assert "".islower() == False
    assert "a".islower() == True
    assert "A".islower() == False
    assert "5".islower() == False
    assert "ahuiuej".islower() == True
    assert "AhUiUeJ".islower() == False
    assert "9735g385497".islower() == True
    assert "9735G385497".islower() == False


def test_isupper():
    """Test str.isupper() method"""
    assert "".isupper() == False
    assert "a".isupper() == False
    assert "A".isupper() == True
    assert "5".isupper() == False
    assert ".J, U-I".isupper() == True
    assert "AHUIUEJ".isupper() == True
    assert "AhUiUeJ".isupper() == False
    assert "9735g385497".isupper() == False
    assert "9735G385497".isupper() == True


def test_isalnum():
    """Test str.isalnum() method"""
    assert "".isalnum() == False
    assert "a".isalnum() == True
    assert "5".isalnum() == True
    assert ",".isalnum() == False
    assert "H6".isalnum() == True
    assert ".J, U-I".isalnum() == False
    assert "A4kki83UE".isalnum() == True
    assert "AhUiUeJ".isalnum() == True
    assert "973 g38597".isalnum() == False
    assert "9735G3-5497".isalnum() == False


def test_isalpha():
    """Test str.isalpha() method"""
    assert "".isalpha() == False
    assert "a".isalpha() == True
    assert "5".isalpha() == False
    assert ",".isalpha() == False
    assert "Hh".isalpha() == True
    assert ".J, U-I".isalpha() == False
    assert "A4kki83UE".isalpha() == False
    assert "AhUiUeJ".isalpha() == True
    assert "973 g38597".isalpha() == False
    assert "9735G3-5497".isalpha() == False


def test_isspace():
    """Test str.isspace() method"""
    assert "".isspace() == False
    assert " ".isspace() == True
    assert "5 ".isspace() == False
    assert "\t\n\r ".isspace() == True
    assert "\t ".isspace() == True
    assert "\t\ngh\r ".isspace() == False
    assert "A4kki 3UE".isspace() == False


def test_istitle():
    """Test str.istitle() method"""
    assert "".istitle() == False
    assert " ".istitle() == False
    assert "I ".istitle() == True
    assert "IH".istitle() == False
    assert "Ih".istitle() == True
    assert "Hter Hewri".istitle() == True
    assert "Kweiur oiejf".istitle() == False


def test_capitalize():
    """Test str.capitalize() method"""
    assert " hello ".capitalize() == " hello "
    assert "Hello ".capitalize() == "Hello "
    assert "hello ".capitalize() == "Hello "
    assert "aaaa".capitalize() == "Aaaa"
    assert "AaAa".capitalize() == "Aaaa"


def test_lower():
    """Test str.lower() method"""
    assert "HeLLo".lower() == "hello"
    assert "hello".lower() == "hello"
    assert "HELLO".lower() == "hello"
    assert "HEL _ LO".lower() == "hel _ lo"


def test_upper():
    """Test str.upper() method"""
    assert "HeLLo".upper() == "HELLO"
    assert "hello".upper() == "HELLO"
    assert "HELLO".upper() == "HELLO"
    assert "HEL _ LO".upper() == "HEL _ LO"


def test_swapcase():
    """Test str.swapcase() method"""
    assert "".swapcase() == ""
    assert "HeLLo cOmpUteRs".swapcase() == "hEllO CoMPuTErS"
    assert "H.e_L,L-o cOmpUteRs".swapcase() == "h.E_l,l-O CoMPuTErS"


def test_title():
    """Test str.title() method"""
    assert "".title() == ""
    assert " hello ".title() == " Hello "
    assert "hello ".title() == "Hello "
    assert "Hello ".title() == "Hello "
    assert "fOrMaT thIs aS titLe String".title() == "Format This As Title String"
    assert "fOrMaT,thIs-aS*titLe;String".title() == "Format,This-As*Title;String"
    assert "getInt".title() == "Getint"


def test_ljust():
    """Test str.ljust() method"""
    assert "abc".ljust(10, " ") == "abc       "
    assert "abc".ljust(6, " ") == "abc   "
    assert "abc".ljust(3, " ") == "abc"
    assert "abc".ljust(2, " ") == "abc"
    assert "abc".ljust(10, "*") == "abc*******"


def test_rjust():
    """Test str.rjust() method"""
    assert "abc".rjust(10, " ") == "       abc"
    assert "abc".rjust(6, " ") == "   abc"
    assert "abc".rjust(3, " ") == "abc"
    assert "abc".rjust(2, " ") == "abc"
    assert "abc".rjust(10, "*") == "*******abc"


def test_center():
    """Test str.center() method"""
    assert "abc".center(10, " ") == "   abc    "
    assert "abc".center(6, " ") == " abc  "
    assert "abc".center(3, " ") == "abc"
    assert "abc".center(2, " ") == "abc"
    assert "abc".center(10, "*") == "***abc****"


def test_zfill():
    """Test str.zfill() method"""
    assert "123".zfill(2) == "123"
    assert "123".zfill(3) == "123"
    assert "123".zfill(4) == "0123"
    assert "+123".zfill(3) == "+123"
    assert "+123".zfill(4) == "+123"
    assert "+123".zfill(5) == "+0123"
    assert "-123".zfill(3) == "-123"
    assert "-123".zfill(4) == "-123"
    assert "-123".zfill(5) == "-0123"
    assert "".zfill(3) == "000"
    assert "34".zfill(1) == "34"
    assert "34".zfill(4) == "0034"


def test_count():
    """Test str.count() method"""
    assert "aaa".count("a") == 3
    assert "aaa".count("b") == 0
    assert "aa".count("aa") == 1
    assert "ababa".count("aba") == 1
    assert "abababa".count("aba") == 2
    assert "abababa".count("abab") == 1


def test_find():
    """Test str.find() method"""
    assert "abcdefghiabc".find("abc") == 0
    assert "abcdefghiabc".find("def") == 3
    assert "abcdefghiabc".find("xyz") == -1
    assert "rrarrrrrrrrra".find("a") == 2
    assert "abc".find("") == 0


def test_rfind():
    """Test str.rfind() method"""
    assert "abcdefghiabc".rfind("abc") == 9
    assert "abcdefghiabc".rfind("") == 12
    assert "abcdefghiabc".rfind("abcd") == 0
    assert "abcdefghiabc".rfind("abcz") == -1
    assert "rrarrrrrrrrra".rfind("a") == 12


def test_lstrip():
    """Test str.lstrip() method"""
    assert "".lstrip() == ""
    assert "   ".lstrip() == ""
    assert "   hello   ".lstrip() == "hello   "
    assert " \t\n\rabc \t\n\r".lstrip() == "abc \t\n\r"
    assert "xyzzyhelloxyzzy".lstrip("xyz") == "helloxyzzy"


def test_rstrip():
    """Test str.rstrip() method"""
    assert "".rstrip() == ""
    assert "   ".rstrip() == ""
    assert "   hello   ".rstrip() == "   hello"
    assert " \t\n\rabc \t\n\r".rstrip() == " \t\n\rabc"
    assert "xyzzyhelloxyzzy".rstrip("xyz") == "xyzzyhello"


def test_strip():
    """Test str.strip() method"""
    assert "".strip() == ""
    assert "   ".strip() == ""
    assert "   hello   ".strip() == "hello"
    assert " \t\n\rabc \t\n\r".strip() == "abc"
    assert "xyzzyhelloxyzzy".strip("xyz") == "hello"
    assert "hello".strip("xyz") == "hello"
    assert "mississippi".strip("mississippi") == ""


def test_split():
    """Test str.split() method"""
    assert "  h    l \t\n l   o ".split() == ["h", "l", "l", "o"]
    assert "h l l o".split(" ") == ["h", "l", "l", "o"]
    assert "a|b|c|d".split("|") == ["a", "b", "c", "d"]
    assert "abcd".split("|") == ["abcd"]
    assert "".split("|") == [""]


def test_rsplit():
    """Test str.rsplit() method"""
    assert "  h    l \t\n l   o ".rsplit() == ["h", "l", "l", "o"]
    assert "a|b|c|d".rsplit("|") == ["a", "b", "c", "d"]
    assert "abcd".rsplit("|") == ["abcd"]
    assert "".rsplit("|") == [""]


def test_startswith():
    """Test str.startswith() method"""
    assert "hello".startswith("he") == True
    assert "hello".startswith("hello") == True
    assert "hello".startswith("hello world") == False
    assert "hello".startswith("") == True
    assert "hello".startswith("ello") == False


def test_endswith():
    """Test str.endswith() method"""
    assert "hello".endswith("lo") == True
    assert "hello".endswith("he") == False
    assert "hello".endswith("") == True
    assert "hello".endswith("hello world") == False


def test_replace():
    """Test str.replace() method"""
    assert "A".replace("", "*") == "*A*"
    assert "AA".replace("", "*-") == "*-A*-A*-"
    assert "A".replace("A", "") == ""
    assert "AAA".replace("A", "") == ""
    assert "Who goes there?".replace("o", "O") == "WhO gOes there?"
    assert "spam, spam, eggs and spam".replace("spam", "ham") == "ham, ham, eggs and ham"


def test_join():
    """Test str.join() method"""
    assert "".join([]) == ""
    assert "a".join([]) == ""
    assert "ab".join(["999"]) == "999"
    assert "xyz".join(["00", "1", "22", "3", "44"]) == "00xyz1xyz22xyz3xyz44"


if __name__ == "__main__":
    test_isdigit(); run("test_isdigit")
    test_islower(); run("test_islower")
    test_isupper(); run("test_isupper")
    test_isalnum(); run("test_isalnum")
    test_isalpha(); run("test_isalpha")
    test_isspace(); run("test_isspace")
    test_istitle(); run("test_istitle")
    test_capitalize(); run("test_capitalize")
    test_lower(); run("test_lower")
    test_upper(); run("test_upper")
    test_swapcase(); run("test_swapcase")
    test_title(); run("test_title")
    test_ljust(); run("test_ljust")
    test_rjust(); run("test_rjust")
    test_center(); run("test_center")
    test_zfill(); run("test_zfill")
    test_count(); run("test_count")
    test_find(); run("test_find")
    test_rfind(); run("test_rfind")
    test_lstrip(); run("test_lstrip")
    test_rstrip(); run("test_rstrip")
    test_strip(); run("test_strip")
    test_split(); run("test_split")
    test_rsplit(); run("test_rsplit")
    test_startswith(); run("test_startswith")
    test_endswith(); run("test_endswith")
    test_replace(); run("test_replace")
    test_join(); run("test_join")

    print(f"\nAll {passed} string tests passed!")
