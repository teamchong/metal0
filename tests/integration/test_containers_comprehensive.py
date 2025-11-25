# Comprehensive container tests from Codon test suite
# Tests for list, dict, tuple, and set operations

# ===== TUPLE TESTS =====

def test_tuple_in_operator():
    results = []
    for i in range(10):
        in_first = i in (4, 9, 10, -1, 3, 1)
        in_second = i in (7,)
        results.append((i, in_first, in_second))
    assert results == [(0, False, False), (1, True, False), (2, False, False), (3, True, False), (4, True, False), (5, False, False), (6, False, False), (7, False, True), (8, False, False), (9, True, False)]

def test_tuple_indexing():
    t = (1, 2, 3)
    assert t[0] == 1
    assert t[1] == 2
    assert t[2] == 3
    assert t[-1] == 3
    assert t[-2] == 2
    assert t[-3] == 1

def test_tuple_slicing():
    t = (1, 2, 3)
    assert t[1:3] == (2, 3)
    assert t[-3:1] == (1,)
    assert t[-10:2] == (1, 2)
    assert t[0:] == (1, 2, 3)
    assert t[-2:] == (2, 3)
    assert t[3:] == ()
    assert t[:-1] == (1, 2)
    assert t[:1] == (1,)
    assert t[:] == (1, 2, 3)
    assert t[::] == (1, 2, 3)
    assert t[1::1] == (2, 3)
    assert t[:2:1] == (1, 2)
    assert t[::2] == (1, 3)
    assert t[::-1] == (3, 2, 1)
    assert t[0:3:-1] == ()
    assert t[3:0:-1] == (3, 2)

def test_tuple_concat():
    assert (1, 2) + (3,) == (1, 2, 3)
    assert (1,) + (2, 3) == (1, 2, 3)
    assert (1, 2) + () == (1, 2)
    assert () + () == ()
    assert () + (1, 2) == (1, 2)
    assert (1,) + (2,) == (1, 2)

def test_tuple_multiply():
    assert (1, 2) * 3 == (1, 2, 1, 2, 1, 2)
    assert () * 99 == ()
    assert (1, 2, 3, 4) * 1 == (1, 2, 3, 4)
    assert (1, 2) * 0 == ()
    assert (1, 2) * (-1) == ()
    assert () * -1 == ()


# ===== LIST TESTS =====

def test_list_comprehension():
    l1 = [i+1 for i in range(100)]
    assert len(l1) == 100
    l1 = l1[98:]
    assert [a for a in l1] == [99, 100]

def test_list_multiply():
    l2 = [1, 2] * 2
    assert [a for a in l2] == [1, 2, 1, 2]
    assert 2 * [1, 2] == [1, 2, 1, 2]

def test_list_indexing_assign():
    l1 = [i*2 for i in range(3)]
    l1.insert(0, 99)
    l1[0] += 1
    del l1[1]
    assert [a for a in l1[0:3]] == [100, 2, 4]

def test_list_remove():
    l3 = [1, 2, 3]
    l3.remove(2)
    assert l3 == [1, 3]

def test_list_insert():
    l5 = [11, 22, 33, 44]
    del l5[-1]
    assert l5 == [11, 22, 33]
    l5.insert(-1, 55)
    l5.insert(1000, 66)
    l5.insert(-100, 77)
    assert l5 == [77, 11, 22, 55, 33, 66]

def test_list_concat():
    l5 = [11, 22, 55, 33]
    assert l5 + [1,2,3] == [11, 22, 55, 33, 1, 2, 3]
    l5 += [1,2,3]
    assert l5 == [11, 22, 55, 33, 1, 2, 3]

def test_list_pop():
    l5 = [11, 22, 55, 33, 1, 2]
    assert l5.pop() == 2
    assert l5 == [11, 22, 55, 33, 1]

def test_list_multiply_assign():
    l5 = [11, 22, 55, 33, 1, 2]
    assert l5 * 2 == [11, 22, 55, 33, 1, 2, 11, 22, 55, 33, 1, 2]
    l5 *= 2
    assert l5 == [11, 22, 55, 33, 1, 2, 11, 22, 55, 33, 1, 2]

def test_list_index():
    l5 = [11, 22, 55, 33, 1, 2, 11, 22, 55, 33, 1, 2]
    assert l5.index(33) == 3
    try:
        l5.index(0)
        assert False
    except ValueError as e:
        assert str(e) == '0 is not in list'

def test_list_extend():
    l6 = []
    l6.extend('abc')
    l6.extend(['xyz'])
    l6.extend('')
    assert l6 == ['a', 'b', 'c', 'xyz']

def test_list_setslice():
    l = [0, 1]
    a = l
    for i in range(-3, 4):
        a[:i] = l[:i]
        assert a == l
        a2 = a[:]
        a2[:i] = a[:i]
        assert a2 == a
        a[i:] = l[i:]
        assert a == l
        a2 = a[:]
        a2[i:] = a[i:]
        assert a2 == a

def test_list_delslice():
    a = [0, 1]
    del a[1:2]
    del a[0:1]
    assert a == []

    a = [0, 1]
    del a[-2:-1]
    assert a == [1]

    a = [0, 1]
    del a[1:]
    del a[:1]
    assert a == []

    a = [0, 1]
    del a[-1:]
    assert a == [0]

    a = [0, 1]
    del a[:]
    assert a == []


# ===== SET TESTS =====

def test_set_comprehension():
    s1 = {a for a in range(100)}
    assert len(s1) == 100
    s1 = {a%8 for a in range(100)}
    for a in range(8):
        assert a in s1
    for a in range(8, 100):
        assert a not in s1

def test_set_remove():
    s1 = {a%8 for a in range(100)}
    assert 5 in s1
    s1.remove(5)
    assert 5 not in s1
    assert len(s1) == 7

def test_set_operations():
    s1 = {1, 2, 3, 4}
    s2 = {2, 3, 4, 5}
    s3 = set()

    assert (s1 | s2) == {1, 2, 3, 4, 5}
    assert (s1 & s2) == {4, 2, 3}
    assert (s1 ^ s2) == {1, 5}
    assert (s1 | s3) == {1, 2, 3, 4}
    assert (s1 & s3) == set()
    assert (s1 ^ s3) == {1, 2, 3, 4}
    assert (s1 - s2) == {1}
    assert (s2 - s1) == {5}

def test_set_comparisons():
    s1 = {1, 2, 3, 4}
    s2 = {2, 3, 4, 5}
    s3 = set()
    assert (s1 > s2) == False
    assert (s1 < s2) == False
    assert (s3 <= s1) == True
    assert (s2 >= s1) == False
    assert ((s1 | s2) > s1) == True

def test_set_pop():
    s1 = {1, 2, 3, 999999}
    s2 = {1, 2, 3, 999999}
    v = s1.pop()
    assert v in s2
    s2.remove(v)
    v = s1.pop()
    assert v in s2


# ===== DICT TESTS =====

def test_dict_comprehension():
    d1 = {a: a*a for a in range(100)}
    assert len(d1) == 100
    d1 = {a: a*a for a in range(5)}
    assert len(d1) == 5

def test_dict_get():
    d1 = {a: a*a for a in range(5)}
    assert [d1.get(a, -1) for a in range(6)] == [0, 1, 4, 9, 16, -1]

def test_dict_delete():
    d1 = {a: a*a for a in range(5)}
    assert 2 in d1
    del d1[2]
    assert 2 not in d1
    d1[2] = 44
    assert 2 in d1
    assert d1.get(2, -1) == 44
    assert d1[3] == 9

def test_dict_items():
    d1 = {0: 0, 1: 1, 2: 44}
    items = [t for t in d1.items()]
    assert (0, 0) in items
    assert (1, 1) in items
    assert (2, 44) in items

def test_dict_union():
    d3 = {1: 2, 42: 42}
    d4 = {1: 5, 2: 9}
    assert d3 | d4 == {1: 5, 42: 42, 2: 9}
    d3 |= d4
    assert d3 == {1: 5, 42: 42, 2: 9}
