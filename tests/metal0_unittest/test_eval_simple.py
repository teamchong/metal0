"""Test eval() functionality"""
import unittest

class TestEval(unittest.TestCase):
    def test_eval_integer(self):
        result = eval("42")
        self.assertEqual(result, 42)

    def test_eval_addition(self):
        result = eval("1 + 2")
        self.assertEqual(result, 3)

    def test_eval_multiplication(self):
        result = eval("3 * 4")
        self.assertEqual(result, 12)

    def test_eval_precedence(self):
        result = eval("1 + 2 * 3")
        self.assertEqual(result, 7)

    def test_eval_parentheses(self):
        result = eval("(1 + 2) * 3")
        self.assertEqual(result, 9)

    def test_eval_subtraction(self):
        result = eval("10 - 4")
        self.assertEqual(result, 6)

    def test_eval_division(self):
        result = eval("15 // 3")
        self.assertEqual(result, 5)

    def test_eval_power(self):
        result = eval("2 ** 3")
        self.assertEqual(result, 8)

if __name__ == "__main__":
    unittest.main()
