"""Comprehensive os module tests for metal0"""
import os
import unittest

class TestOsPath(unittest.TestCase):
    def test_getcwd(self):
        cwd = os.getcwd()
        self.assertTrue(len(cwd) > 0)

    def test_getcwd_absolute(self):
        cwd = os.getcwd()
        self.assertTrue(cwd.startswith("/"))

class TestOsPathExists(unittest.TestCase):
    def test_path_exists_dot(self):
        self.assertTrue(os.path.exists("."))

    def test_path_exists_false(self):
        self.assertFalse(os.path.exists("/nonexistent/path/12345"))

class TestOsPathIsdir(unittest.TestCase):
    def test_isdir_dot(self):
        self.assertTrue(os.path.isdir("."))

    def test_isdir_file(self):
        # This file itself should not be a directory
        self.assertFalse(os.path.isdir("tests/metal0_stdlib/test_os_simple.py"))

class TestOsPathBasename(unittest.TestCase):
    def test_basename_simple(self):
        self.assertEqual(os.path.basename("/usr/bin/python"), "python")

    def test_basename_no_dir(self):
        self.assertEqual(os.path.basename("file.txt"), "file.txt")

class TestOsPathDirname(unittest.TestCase):
    def test_dirname_simple(self):
        self.assertEqual(os.path.dirname("/usr/bin/python"), "/usr/bin")

    def test_dirname_no_dir(self):
        self.assertEqual(os.path.dirname("file.txt"), "")

if __name__ == "__main__":
    unittest.main()
