"""Comprehensive statistics module tests for metal0"""
import statistics
import unittest

class TestStatisticsMean(unittest.TestCase):
    def test_mean_integers(self):
        result = statistics.mean([1, 2, 3, 4, 5])
        self.assertEqual(result, 3.0)

    def test_mean_even(self):
        result = statistics.mean([2, 4, 6, 8])
        self.assertEqual(result, 5.0)

    def test_mean_single(self):
        result = statistics.mean([42])
        self.assertEqual(result, 42.0)

    def test_mean_large(self):
        result = statistics.mean([100, 200, 300])
        self.assertEqual(result, 200.0)

class TestStatisticsMedian(unittest.TestCase):
    def test_median_odd(self):
        result = statistics.median([1, 3, 5])
        self.assertEqual(result, 3.0)

    def test_median_even(self):
        result = statistics.median([1, 2, 3, 4])
        self.assertEqual(result, 2.5)

    def test_median_single(self):
        result = statistics.median([7])
        self.assertEqual(result, 7.0)

    def test_median_unsorted(self):
        result = statistics.median([3, 1, 2])
        self.assertEqual(result, 2.0)

class TestStatisticsVariance(unittest.TestCase):
    def test_pvariance(self):
        result = statistics.pvariance([2, 4, 4, 4, 5, 5, 7, 9])
        self.assertTrue(result > 0)

    def test_pstdev(self):
        result = statistics.pstdev([2, 4, 4, 4, 5, 5, 7, 9])
        self.assertTrue(result > 0)

    def test_variance(self):
        result = statistics.variance([2, 4, 4, 4, 5, 5, 7, 9])
        self.assertTrue(result > 0)

    def test_stdev(self):
        result = statistics.stdev([2, 4, 4, 4, 5, 5, 7, 9])
        self.assertTrue(result > 0)

class TestStatisticsMode(unittest.TestCase):
    def test_mode_basic(self):
        result = statistics.mode([1, 1, 2, 3])
        self.assertIsNotNone(result)

if __name__ == "__main__":
    unittest.main()
