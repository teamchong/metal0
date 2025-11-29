"""Comprehensive random module tests for metal0"""
import random
import unittest

class TestRandomBasic(unittest.TestCase):
    def test_random(self):
        # random() returns float in [0.0, 1.0)
        x = random.random()
        self.assertTrue(x >= 0.0)
        self.assertTrue(x < 1.0)

    def test_random_again(self):
        # random() returns float in [0.0, 1.0)
        x = random.random()
        self.assertTrue(x >= 0.0)
        self.assertTrue(x < 1.0)

class TestRandomInt(unittest.TestCase):
    def test_randint_range(self):
        x = random.randint(1, 10)
        self.assertTrue(x >= 1)
        self.assertTrue(x <= 10)

    def test_randint_single_value(self):
        x = random.randint(5, 5)
        self.assertEqual(x, 5)

    def test_randint_large_range(self):
        x = random.randint(1, 1000000)
        self.assertTrue(x >= 1)
        self.assertTrue(x <= 1000000)

    def test_randint_negative(self):
        x = random.randint(-100, -1)
        self.assertTrue(x >= -100)
        self.assertTrue(x <= -1)

class TestRandomRange(unittest.TestCase):
    def test_randrange_single_arg(self):
        x = random.randrange(10)
        self.assertTrue(x >= 0)
        self.assertTrue(x < 10)

    def test_randrange_two_args(self):
        x = random.randrange(5, 15)
        self.assertTrue(x >= 5)
        self.assertTrue(x < 15)

class TestRandomUniform(unittest.TestCase):
    def test_uniform_0_1(self):
        x = random.uniform(0.0, 1.0)
        self.assertTrue(x >= 0.0)
        self.assertTrue(x <= 1.0)

    def test_uniform_range(self):
        x = random.uniform(10.0, 20.0)
        self.assertTrue(x >= 10.0)
        self.assertTrue(x <= 20.0)

    def test_uniform_negative(self):
        x = random.uniform(-10.0, 0.0)
        self.assertTrue(x >= -10.0)
        self.assertTrue(x <= 0.0)

class TestRandomChoice(unittest.TestCase):
    def test_choice_list(self):
        items = [1, 2, 3, 4, 5]
        x = random.choice(items)
        self.assertTrue(x >= 1)
        self.assertTrue(x <= 5)

    def test_choice_list_2(self):
        items = [10, 20, 30]
        x = random.choice(items)
        is_valid = (x == 10) or (x == 20) or (x == 30)
        self.assertTrue(is_valid)

if __name__ == "__main__":
    unittest.main()
