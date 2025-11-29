"""Comprehensive random module tests for metal0"""
import random
import unittest

class TestRandomBasic(unittest.TestCase):
    def test_random_range(self):
        r = random.random()
        self.assertTrue(0 <= r < 1)

    def test_random_positive(self):
        r = random.random()
        self.assertTrue(r >= 0)

    def test_random_less_than_one(self):
        r = random.random()
        self.assertTrue(r < 1)

class TestRandomInt(unittest.TestCase):
    def test_randint_range(self):
        r = random.randint(1, 10)
        self.assertTrue(1 <= r <= 10)

    def test_randint_single(self):
        r = random.randint(5, 5)
        self.assertEqual(r, 5)

    def test_randint_negative(self):
        r = random.randint(-10, -1)
        self.assertTrue(-10 <= r <= -1)

    def test_randint_zero(self):
        r = random.randint(0, 100)
        self.assertTrue(0 <= r <= 100)

class TestRandomRange(unittest.TestCase):
    def test_randrange_basic(self):
        r = random.randrange(10)
        self.assertTrue(0 <= r < 10)

    def test_randrange_start_stop(self):
        r = random.randrange(5, 15)
        self.assertTrue(5 <= r < 15)

class TestRandomUniform(unittest.TestCase):
    def test_uniform_range(self):
        r = random.uniform(1.0, 2.0)
        self.assertTrue(1.0 <= r <= 2.0)

    def test_uniform_negative(self):
        r = random.uniform(-5.0, -1.0)
        self.assertTrue(-5.0 <= r <= -1.0)

    def test_uniform_zero(self):
        r = random.uniform(0.0, 1.0)
        self.assertTrue(0.0 <= r <= 1.0)

class TestRandomSeed(unittest.TestCase):
    def test_seed_reproducible(self):
        random.seed(42)
        r1 = random.random()
        random.seed(42)
        r2 = random.random()
        self.assertEqual(r1, r2)

if __name__ == "__main__":
    unittest.main()
