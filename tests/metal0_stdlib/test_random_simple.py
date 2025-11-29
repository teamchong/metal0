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

    def test_randrange_step(self):
        r = random.randrange(0, 10, 2)
        self.assertTrue(r in [0, 2, 4, 6, 8])

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

class TestRandomChoice(unittest.TestCase):
    def test_choice_list(self):
        choices = [1, 2, 3, 4, 5]
        r = random.choice(choices)
        self.assertIn(r, choices)

    def test_choice_single(self):
        choices = [42]
        r = random.choice(choices)
        self.assertEqual(r, 42)

class TestRandomSeed(unittest.TestCase):
    def test_seed_reproducible(self):
        random.seed(42)
        r1 = random.random()
        random.seed(42)
        r2 = random.random()
        self.assertEqual(r1, r2)

    def test_seed_different(self):
        random.seed(1)
        r1 = random.random()
        random.seed(2)
        r2 = random.random()
        self.assertNotEqual(r1, r2)

class TestRandomShuffle(unittest.TestCase):
    def test_shuffle_length(self):
        lst = [1, 2, 3, 4, 5]
        random.shuffle(lst)
        self.assertEqual(len(lst), 5)

    def test_shuffle_elements(self):
        lst = [1, 2, 3, 4, 5]
        random.shuffle(lst)
        self.assertEqual(sorted(lst), [1, 2, 3, 4, 5])

class TestRandomSample(unittest.TestCase):
    def test_sample_length(self):
        lst = [1, 2, 3, 4, 5]
        s = random.sample(lst, 3)
        self.assertEqual(len(s), 3)

    def test_sample_subset(self):
        lst = [1, 2, 3, 4, 5]
        s = random.sample(lst, 2)
        for item in s:
            self.assertIn(item, lst)

if __name__ == "__main__":
    unittest.main()
