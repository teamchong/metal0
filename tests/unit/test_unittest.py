import unittest

class TestAssertions(unittest.TestCase):
    def test_equal(self):
        self.assertEqual(1, 1)
        self.assertEqual("hello", "hello")

    def test_true(self):
        self.assertTrue(True)
        self.assertTrue(1 == 1)

    def test_false(self):
        self.assertFalse(False)
        self.assertFalse(1 == 2)

    def test_greater(self):
        self.assertGreater(5, 3)
        self.assertGreater(10, 1)

    def test_less(self):
        self.assertLess(3, 5)
        self.assertLess(1, 10)

    def test_greater_equal(self):
        self.assertGreaterEqual(5, 5)
        self.assertGreaterEqual(5, 3)

    def test_less_equal(self):
        self.assertLessEqual(3, 3)
        self.assertLessEqual(3, 5)

    def test_not_equal(self):
        self.assertNotEqual(1, 2)
        self.assertNotEqual("hello", "world")

    def test_in(self):
        self.assertIn(1, [1, 2, 3])
        self.assertIn(2, [1, 2, 3])

    def test_not_in(self):
        self.assertNotIn(5, [1, 2, 3])
        self.assertNotIn(0, [1, 2, 3])

    def test_not_none(self):
        self.assertIsNotNone(42)
        self.assertIsNotNone("hello")

    def test_almost_equal(self):
        self.assertAlmostEqual(1.0000001, 1.0000002)
        self.assertAlmostEqual(3.14159265, 3.14159265)

    def test_not_almost_equal(self):
        self.assertNotAlmostEqual(1.0, 2.0)
        self.assertNotAlmostEqual(0.0, 1.0)

    def test_count_equal(self):
        self.assertCountEqual([1, 2, 3], [3, 2, 1])
        self.assertCountEqual([5, 5, 5], [5, 5, 5])

class TestSetup(unittest.TestCase):
    def setUp(self):
        self.value = 42

    def test_setup_ran(self):
        self.assertEqual(self.value, 42)

unittest.main()
