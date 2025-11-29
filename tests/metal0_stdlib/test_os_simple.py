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

class TestOsEnviron(unittest.TestCase):
    def test_environ_exists(self):
        self.assertIsNotNone(os.environ)

    def test_environ_path(self):
        self.assertIn("PATH", os.environ)

class TestOsName(unittest.TestCase):
    def test_name_posix(self):
        self.assertEqual(os.name, "posix")

class TestOsSep(unittest.TestCase):
    def test_sep_slash(self):
        self.assertEqual(os.sep, "/")

    def test_pathsep_colon(self):
        self.assertEqual(os.pathsep, ":")

    def test_linesep(self):
        self.assertIn(os.linesep, ["\n", "\r\n"])

if __name__ == "__main__":
    unittest.main()
