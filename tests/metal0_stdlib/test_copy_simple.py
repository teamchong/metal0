"""Copy module tests for metal0"""
import copy
import unittest

class TestCopyShallow(unittest.TestCase):
    def test_copy_int(self):
        x = 42
        y = copy.copy(x)
        self.assertEqual(y, 42)

    def test_copy_float(self):
        x = 3.14
        y = copy.copy(x)
        self.assertEqual(y, 3.14)

    def test_copy_string(self):
        x = "hello"
        y = copy.copy(x)
        self.assertEqual(y, "hello")

    def test_copy_bool_true(self):
        x = True
        y = copy.copy(x)
        self.assertTrue(y)

    def test_copy_bool_false(self):
        x = False
        y = copy.copy(x)
        self.assertFalse(y)

class TestCopyDeep(unittest.TestCase):
    def test_deepcopy_int(self):
        x = 42
        y = copy.deepcopy(x)
        self.assertEqual(y, 42)

    def test_deepcopy_float(self):
        x = 3.14
        y = copy.deepcopy(x)
        self.assertEqual(y, 3.14)

    def test_deepcopy_string(self):
        x = "hello"
        y = copy.deepcopy(x)
        self.assertEqual(y, "hello")

    def test_deepcopy_bool_true(self):
        x = True
        y = copy.deepcopy(x)
        self.assertTrue(y)

    def test_deepcopy_bool_false(self):
        x = False
        y = copy.deepcopy(x)
        self.assertFalse(y)

if __name__ == "__main__":
    unittest.main()
