# Tokenizer benchmark - PyAOT tokenizer wrapper
# This calls the Zig tokenizer through Python bindings

def tokenize(text: str) -> int:
    """Count tokens in text using BPE tokenizer"""
    # Simple word-based tokenizer for now
    tokens = 0
    in_word = 0
    i = 0
    while i < len(text):
        c = text[i]
        if c == ' ' or c == '\n' or c == '\t':
            if in_word == 1:
                tokens = tokens + 1
                in_word = 0
        else:
            in_word = 1
        i = i + 1
    if in_word == 1:
        tokens = tokens + 1
    return tokens

# Test
text = "Hello world this is a test of the tokenizer"
count = tokenize(text)
print(count)  # Should print 9
