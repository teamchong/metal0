"""Comprehensive json module tests for metal0"""
import json
import unittest

class TestJsonDumps(unittest.TestCase):
    def test_dumps_string(self):
        result = json.dumps("hello")
        self.assertEqual(result, '"hello"')

    def test_dumps_int(self):
        result = json.dumps(42)
        self.assertEqual(result, "42")

    def test_dumps_float(self):
        result = json.dumps(3.14)
        self.assertEqual(result, "3.14")

    def test_dumps_bool_true(self):
        result = json.dumps(True)
        self.assertEqual(result, "true")

    def test_dumps_bool_false(self):
        result = json.dumps(False)
        self.assertEqual(result, "false")

    def test_dumps_none(self):
        result = json.dumps(None)
        self.assertEqual(result, "null")

    def test_dumps_list(self):
        result = json.dumps([1, 2, 3])
        self.assertEqual(result, "[1, 2, 3]")

class TestJsonLoads(unittest.TestCase):
    def test_loads_string(self):
        result = json.loads('"hello"')
        self.assertEqual(result, "hello")

    def test_loads_int(self):
        result = json.loads("42")
        self.assertEqual(result, 42)

    def test_loads_bool_true(self):
        result = json.loads("true")
        self.assertEqual(result, True)

    def test_loads_bool_false(self):
        result = json.loads("false")
        self.assertEqual(result, False)

    def test_loads_null(self):
        result = json.loads("null")
        self.assertIsNone(result)

    def test_loads_list(self):
        result = json.loads("[1, 2, 3]")
        self.assertEqual(result, [1, 2, 3])

    def test_loads_empty_list(self):
        result = json.loads("[]")
        self.assertEqual(result, [])

if __name__ == "__main__":
    unittest.main()
