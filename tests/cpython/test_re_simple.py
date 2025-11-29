"""Simple re module tests for metal0"""
import re
import unittest

class TestReBasic(unittest.TestCase):
    def test_search(self):
        result = re.search(r'\d+', 'hello 123 world')
        self.assertIsNotNone(result)
        # Use group() with no args
        text = result.group()
        self.assertEqual(text, '123')
    
    def test_match(self):
        result = re.match(r'\d+', '123 hello')
        self.assertIsNotNone(result)
        self.assertEqual(result.group(), '123')
        
        result2 = re.match(r'\d+', 'hello 123')
        self.assertIsNone(result2)
    
    def test_findall(self):
        result = re.findall(r'\d+', 'a1b2c3')
        self.assertEqual(result, ['1', '2', '3'])
    
    def test_sub(self):
        result = re.sub(r'\d+', 'X', 'a1b2c3')
        self.assertEqual(result, 'aXbXcX')
    
    def test_split(self):
        result = re.split(r'\s+', 'hello world  foo')
        self.assertEqual(result, ['hello', 'world', 'foo'])

if __name__ == "__main__":
    unittest.main()
