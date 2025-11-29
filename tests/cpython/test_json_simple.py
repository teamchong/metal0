"""Simple json module tests for metal0"""
import json
import unittest

class TestJsonDumps(unittest.TestCase):
    def test_dumps_string(self):
        self.assertEqual(json.dumps("hello"), '"hello"')

    def test_dumps_int(self):
        self.assertEqual(json.dumps(42), '42')

    def test_dumps_float(self):
        self.assertEqual(json.dumps(3.14), '3.14')

    def test_dumps_bool_true(self):
        self.assertEqual(json.dumps(True), 'true')

    def test_dumps_bool_false(self):
        self.assertEqual(json.dumps(False), 'false')

    def test_dumps_none(self):
        self.assertEqual(json.dumps(None), 'null')

    def test_dumps_list(self):
        result = json.dumps([1, 2, 3])
        self.assertIn('1', result)
        self.assertIn('2', result)
        self.assertIn('3', result)

    def test_dumps_dict(self):
        result = json.dumps({"a": 1})
        self.assertIn('"a"', result)
        self.assertIn('1', result)

if __name__ == "__main__":
    unittest.main()
