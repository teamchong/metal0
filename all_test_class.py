"Test the functionality of Python classes implementing operators."

import unittest
from test.support import cpython_only, import_helper, script_helper

callLst = []
def trackCall(f):
    def track(*args, **kwargs):
        callLst.append((f.__name__, args))
        return f(*args, **kwargs)
    return track

class AllTests:
    def __hash__(self):
        callLst.append(('__hash__', (self,)))
        return hash(id(self))
    def __str__(self):
        callLst.append(('__str__', (self,)))
        return 'AllTests'
    def __repr__(self):
        callLst.append(('__repr__', (self,)))
        return 'AllTests'
    def __int__(self):
        callLst.append(('__int__', (self,)))
        return 1
    def __index__(self):
        callLst.append(('__index__', (self,)))
        return 1
    def __float__(self):
        callLst.append(('__float__', (self,)))
        return 1.0
    def __eq__(self, arg0):
        callLst.append(('__eq__', (self, arg0,)))
        return True
    def __ne__(self, arg0):
        callLst.append(('__ne__', (self, arg0,)))
        return False
    def __lt__(self, arg0):
        callLst.append(('__lt__', (self, arg0,)))
        return False
    def __le__(self, arg0):
        callLst.append(('__le__', (self, arg0,)))
        return True
    def __gt__(self, arg0):
        callLst.append(('__gt__', (self, arg0,)))
        return False
    def __ge__(self, arg0):
        callLst.append(('__ge__', (self, arg0,)))
        return True
    def __setitem__(self, arg0, arg1):
        callLst.append(('__setitem__', (self, arg0, arg1,)))
        pass
    def __delitem__(self, arg0):
        callLst.append(('__delitem__', (self, arg0,)))
        pass
    def __init__(self):
        callLst.append(('__init__', (self,)))
        pass
    def __add__(self, other):
        callLst.append(('__add__', (self, other)))
        pass
    def __radd__(self, other):
        callLst.append(('__radd__', (self, other)))
        pass
    def __sub__(self, other):
        callLst.append(('__sub__', (self, other)))
        pass
    def __rsub__(self, other):
        callLst.append(('__rsub__', (self, other)))
        pass
    def __mul__(self, other):
        callLst.append(('__mul__', (self, other)))
        pass
    def __rmul__(self, other):
        callLst.append(('__rmul__', (self, other)))
        pass
    def __matmul__(self, other):
        callLst.append(('__matmul__', (self, other)))
        pass
    def __rmatmul__(self, other):
        callLst.append(('__rmatmul__', (self, other)))
        pass
    def __truediv__(self, other):
        callLst.append(('__truediv__', (self, other)))
        pass
    def __rtruediv__(self, other):
        callLst.append(('__rtruediv__', (self, other)))
        pass
    def __floordiv__(self, other):
        callLst.append(('__floordiv__', (self, other)))
        pass
    def __rfloordiv__(self, other):
        callLst.append(('__rfloordiv__', (self, other)))
        pass
    def __mod__(self, other):
        callLst.append(('__mod__', (self, other)))
        pass
    def __rmod__(self, other):
        callLst.append(('__rmod__', (self, other)))
        pass
    def __divmod__(self, other):
        callLst.append(('__divmod__', (self, other)))
        pass
    def __rdivmod__(self, other):
        callLst.append(('__rdivmod__', (self, other)))
        pass
    def __pow__(self, other):
        callLst.append(('__pow__', (self, other)))
        pass
    def __rpow__(self, other):
        callLst.append(('__rpow__', (self, other)))
        pass
    def __rshift__(self, other):
        callLst.append(('__rshift__', (self, other)))
        pass
    def __rrshift__(self, other):
        callLst.append(('__rrshift__', (self, other)))
        pass
    def __lshift__(self, other):
        callLst.append(('__lshift__', (self, other)))
        pass
    def __rlshift__(self, other):
        callLst.append(('__rlshift__', (self, other)))
        pass
    def __and__(self, other):
        callLst.append(('__and__', (self, other)))
        pass
    def __rand__(self, other):
        callLst.append(('__rand__', (self, other)))
        pass
    def __or__(self, other):
        callLst.append(('__or__', (self, other)))
        pass
    def __ror__(self, other):
        callLst.append(('__ror__', (self, other)))
        pass
    def __xor__(self, other):
        callLst.append(('__xor__', (self, other)))
        pass
    def __rxor__(self, other):
        callLst.append(('__rxor__', (self, other)))
        pass
    def __contains__(self, other):
        callLst.append(('__contains__', (self, other)))
        pass
    def __getitem__(self, other):
        callLst.append(('__getitem__', (self, other)))
        pass
    def __neg__(self):
        callLst.append(('__neg__', (self,)))
        pass
    def __pos__(self):
        callLst.append(('__pos__', (self,)))
        pass
    def __abs__(self):
        callLst.append(('__abs__', (self,)))
        pass

class ClassTests(unittest.TestCase):
    def setUp(self):
        callLst[:] = []

    def assertCallStack(self, expected_calls):
        actualCallList = callLst[:]  # need to copy because the comparison below will add
                                     # additional calls to callLst
        if expected_calls != actualCallList:
            self.fail("Expected call list:\n  %s\ndoes not match actual call list\n  %s" %
                      (expected_calls, actualCallList))

    def testInit(self):
        foo = AllTests()
        self.assertCallStack([("__init__", (foo,))])

    def testBinaryOps(self):
        testme = AllTests()
        # Binary operations

        callLst[:] = []
        testme + 1
        self.assertCallStack([("__add__", (testme, 1))])

        callLst[:] = []
        1 + testme
        self.assertCallStack([("__radd__", (testme, 1))])

        callLst[:] = []
        testme - 1
        self.assertCallStack([("__sub__", (testme, 1))])

        callLst[:] = []
        1 - testme
        self.assertCallStack([("__rsub__", (testme, 1))])

        callLst[:] = []
        testme * 1
        self.assertCallStack([("__mul__", (testme, 1))])

        callLst[:] = []
        1 * testme
        self.assertCallStack([("__rmul__", (testme, 1))])

        callLst[:] = []
        testme @ 1
        self.assertCallStack([("__matmul__", (testme, 1))])

        callLst[:] = []
        1 @ testme
        self.assertCallStack([("__rmatmul__", (testme, 1))])

        callLst[:] = []
        testme / 1
        self.assertCallStack([("__truediv__", (testme, 1))])


        callLst[:] = []
        1 / testme
        self.assertCallStack([("__rtruediv__", (testme, 1))])

        callLst[:] = []
        testme // 1
        self.assertCallStack([("__floordiv__", (testme, 1))])

        callLst[:] = []
        1 // testme
        self.assertCallStack([("__rfloordiv__", (testme, 1))])

        callLst[:] = []
        testme % 1
        self.assertCallStack([("__mod__", (testme, 1))])

        callLst[:] = []
        1 % testme
        self.assertCallStack([("__rmod__", (testme, 1))])

        callLst[:] = []
        divmod(testme, 1)
        self.assertCallStack([("__divmod__", (testme, 1))])

        callLst[:] = []
        divmod(1, testme)
        self.assertCallStack([("__rdivmod__", (testme, 1))])

        callLst[:] = []
        testme ** 1
        self.assertCallStack([("__pow__", (testme, 1))])

        callLst[:] = []
        1 ** testme
        self.assertCallStack([("__rpow__", (testme, 1))])

        callLst[:] = []
        testme >> 1
        self.assertCallStack([("__rshift__", (testme, 1))])

        callLst[:] = []
        1 >> testme
        self.assertCallStack([("__rrshift__", (testme, 1))])

        callLst[:] = []
        testme << 1
        self.assertCallStack([("__lshift__", (testme, 1))])

        callLst[:] = []
        1 << testme
        self.assertCallStack([("__rlshift__", (testme, 1))])

        callLst[:] = []
        testme & 1
        self.assertCallStack([("__and__", (testme, 1))])

        callLst[:] = []
        1 & testme
        self.assertCallStack([("__rand__", (testme, 1))])

        callLst[:] = []
        testme | 1
        self.assertCallStack([("__or__", (testme, 1))])

        callLst[:] = []
        1 | testme
        self.assertCallStack([("__ror__", (testme, 1))])

        callLst[:] = []
        testme ^ 1
        self.assertCallStack([("__xor__", (testme, 1))])

        callLst[:] = []
        1 ^ testme
        self.assertCallStack([("__rxor__", (testme, 1))])


    def testListAndDictOps(self):
        testme = AllTests()

        # List/dict operations

        callLst[:] = []
        1 in testme
        self.assertCallStack([("__contains__", (testme, 1))])

        callLst[:] = []
        testme[1]
        self.assertCallStack([("__getitem__", (testme, 1))])

        callLst[:] = []
        testme[1] = 1
        self.assertCallStack([("__setitem__", (testme, 1, 1))])

        callLst[:] = []
        del testme[1]
        self.assertCallStack([("__delitem__", (testme, 1))])


    def testUnaryOps(self):
        testme = AllTests()

        # Unary operations

        callLst[:] = []
        -testme
        self.assertCallStack([("__neg__", (testme,))])

        callLst[:] = []
        +testme
        self.assertCallStack([("__pos__", (testme,))])

        callLst[:] = []
        abs(testme)
        self.assertCallStack([("__abs__", (testme,))])

        # callLst[:] = []
        # ~testme
        # self.assertCallStack([("__invert__", (testme,))])


    def testRichComparisonOps(self):
        testme = AllTests()

        # Rich comparison operations

        callLst[:] = []
        testme == 1
        self.assertCallStack([("__eq__", (testme, 1))])

        callLst[:] = []
        testme != 1
        self.assertCallStack([("__ne__", (testme, 1))])

        callLst[:] = []
        testme < 1
        self.assertCallStack([("__lt__", (testme, 1))])

        callLst[:] = []
        testme <= 1
        self.assertCallStack([("__le__", (testme, 1))])

        callLst[:] = []
        testme > 1
        self.assertCallStack([("__gt__", (testme, 1))])

        callLst[:] = []
        testme >= 1
        self.assertCallStack([("__ge__", (testme, 1))])


    def testOtherOps(self):
        testme = AllTests()

        # Other operations

        callLst[:] = []
        hash(testme)
        self.assertCallStack([("__hash__", (testme,))])

        callLst[:] = []
        str(testme)
        self.assertCallStack([("__str__", (testme,))])

        callLst[:] = []
        repr(testme)
        self.assertCallStack([("__repr__", (testme,))])

        callLst[:] = []
        int(testme)
        self.assertCallStack([("__int__", (testme,))])

        # callLst[:] = []
        # float(testme)
        # self.assertCallStack([("__float__", (testme,))])

        callLst[:] = []
        import operator
        operator.index(testme)
        self.assertCallStack([("__index__", (testme,))])


    def testGetSetAndDel(self):
        # r2 = AllTests()
        # r2.x = 1
        # self.assertEqual(r2.x, 1)
        # del r2.x
        # self.assertRaises(AttributeError, getattr, r2, 'x')
        pass

    # def testDel(self):
    #     foo = AllTests()
    #     del foo

    # def test_store_attr_type_cache(self):
    #     # See GH-92140.
    #     class C:
    #         pass
    #     def store_attr(obj, val):
    #         obj.attr = val
    #     c = C()
    #     store_attr(c, 1)
    #     self.assertEqual(c.attr, 1)
    #     C.__setattr__ = lambda self, name, value: None
    #     store_attr(c, 2)
    #     self.assertEqual(c.attr, 1)

    # def testObjectAttributeAccessErrorMessages(self):
    #     class C:
    #         pass
    #     obj = C()
    #     with self.assertRaisesRegex(AttributeError, "'C' object has no attribute 'x'"):
    #         obj.x
    #     with self.assertRaisesRegex(AttributeError, "'C' object has no attribute 'x'"):
    #         del obj.x

    # def testConstructorErrorMessages(self):
    #     with self.assertRaisesRegex(TypeError, "C\(\) takes no arguments"):
    #         class C: pass
    #         C(1)
    #     with self.assertRaisesRegex(TypeError, "C\(\) takes no arguments"):
    #         class C: pass
    #         C(a=1)

    # def testMisc(self):
    #     # Global attribute access
    #     self.assertEqual(AllTests.__name__, "AllTests")
    #     self.assertEqual(AllTests.__doc__, None)

if __name__ == "__main__":
    unittest.main()
