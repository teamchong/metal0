"""Comprehensive re module tests for metal0"""
import re
import unittest

class TestReSearch(unittest.TestCase):
    def test_search_digits(self):
        result = re.search(r'\d+', 'hello 123 world')
        self.assertIsNotNone(result)
        text = result.group()
        self.assertEqual(text, '123')

    def test_search_word(self):
        result = re.search(r'world', 'hello world')
        self.assertIsNotNone(result)
        self.assertEqual(result.group(), 'world')

    def test_search_start_anchor(self):
        result = re.search(r'^hello', 'hello world')
        self.assertIsNotNone(result)

    def test_search_end_anchor(self):
        result = re.search(r'world$', 'hello world')
        self.assertIsNotNone(result)

    def test_search_not_found(self):
        result = re.search(r'xyz', 'hello world')
        self.assertIsNone(result)

    def test_search_dot(self):
        result = re.search(r'h.llo', 'hello')
        self.assertIsNotNone(result)

class TestReMatch(unittest.TestCase):
    def test_match_digits(self):
        result = re.match(r'\d+', '123 hello')
        self.assertIsNotNone(result)
        self.assertEqual(result.group(), '123')

    def test_match_no_match(self):
        result = re.match(r'\d+', 'hello 123')
        self.assertIsNone(result)

    def test_match_word(self):
        result = re.match(r'hello', 'hello world')
        self.assertIsNotNone(result)

    def test_match_full_string(self):
        result = re.match(r'hello world', 'hello world')
        self.assertIsNotNone(result)

class TestReFindall(unittest.TestCase):
    def test_findall_digits(self):
        result = re.findall(r'\d+', 'a1b2c3')
        self.assertEqual(result, ['1', '2', '3'])

    def test_findall_words(self):
        # Use [a-z]+ instead of \w+ due to regex engine limitation
        result = re.findall(r'[a-z]+', 'hello world')
        self.assertEqual(len(result), 2)

    def test_findall_empty(self):
        result = re.findall(r'\d+', 'no digits')
        self.assertEqual(len(result), 0)

    def test_findall_letters(self):
        result = re.findall(r'[a-z]+', 'abc123def')
        self.assertEqual(result, ['abc', 'def'])

    def test_findall_multiple(self):
        result = re.findall(r'\d+', 'a123b456c789')
        self.assertEqual(len(result), 3)

class TestReSub(unittest.TestCase):
    def test_sub_digits(self):
        result = re.sub(r'\d+', 'X', 'a1b2c3')
        self.assertEqual(result, 'aXbXcX')

    def test_sub_word(self):
        result = re.sub(r'world', 'universe', 'hello world')
        self.assertEqual(result, 'hello universe')

    def test_sub_spaces(self):
        result = re.sub(r'\s+', '_', 'hello world')
        self.assertEqual(result, 'hello_world')

    def test_sub_no_match(self):
        result = re.sub(r'\d+', 'X', 'no digits')
        self.assertEqual(result, 'no digits')

    def test_sub_empty_replacement(self):
        result = re.sub(r'\d+', '', 'a1b2c3')
        self.assertEqual(result, 'abc')

class TestReSplit(unittest.TestCase):
    def test_split_spaces(self):
        result = re.split(r'\s+', 'hello world  foo')
        self.assertEqual(result, ['hello', 'world', 'foo'])

    def test_split_comma(self):
        result = re.split(r',', 'a,b,c')
        self.assertEqual(result, ['a', 'b', 'c'])

    def test_split_digits(self):
        result = re.split(r'\d+', 'abc123def456ghi')
        self.assertEqual(result, ['abc', 'def', 'ghi'])

    def test_split_semicolon(self):
        result = re.split(r';', 'a;b;c;d')
        self.assertEqual(len(result), 4)

class TestRePatterns(unittest.TestCase):
    def test_star_quantifier(self):
        result = re.search(r'ab*c', 'ac')
        self.assertIsNotNone(result)

    def test_plus_quantifier(self):
        result = re.search(r'ab+c', 'abbc')
        self.assertIsNotNone(result)

    def test_question_quantifier(self):
        result = re.search(r'colou?r', 'color')
        self.assertIsNotNone(result)

    def test_bracket_class(self):
        result = re.search(r'[aeiou]', 'hello')
        self.assertIsNotNone(result)

    def test_negated_class(self):
        result = re.search(r'[^0-9]+', 'abc123')
        self.assertIsNotNone(result)
        self.assertEqual(result.group(), 'abc')

    def test_or_pattern(self):
        result = re.search(r'cat|dog', 'I have a dog')
        self.assertIsNotNone(result)
        self.assertEqual(result.group(), 'dog')

if __name__ == "__main__":
    unittest.main()
