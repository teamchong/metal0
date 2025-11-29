"""Simple os module tests for metal0"""
import os
import unittest

class TestOsPath(unittest.TestCase):
    def test_path_join(self):
        result = os.path.join("a", "b")
        self.assertEqual(result, "a/b")

    def test_path_join_three(self):
        result = os.path.join("a", "b", "c")
        self.assertEqual(result, "a/b/c")

    def test_path_basename(self):
        result = os.path.basename("/path/to/file.txt")
        self.assertEqual(result, "file.txt")

    def test_path_dirname(self):
        result = os.path.dirname("/path/to/file.txt")
        self.assertEqual(result, "/path/to")

    def test_path_exists(self):
        # Current file should exist
        self.assertTrue(os.path.exists("."))

    def test_path_isdir(self):
        self.assertTrue(os.path.isdir("."))

    def test_path_abspath(self):
        result = os.path.abspath(".")
        self.assertTrue(len(result) > 0)

class TestOsGetenv(unittest.TestCase):
    def test_getenv(self):
        # PATH should exist
        path = os.getenv("PATH")
        self.assertIsNotNone(path)

    def test_getenv_default(self):
        # Non-existent var should return default
        result = os.getenv("NONEXISTENT_VAR_12345", "default")
        self.assertEqual(result, "default")

if __name__ == "__main__":
    unittest.main()
