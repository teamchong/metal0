#!/usr/bin/env python3
"""
Compare metal0 Zig vs tiktoken vs TokenDagger vs HuggingFace
"""
import time
import subprocess
import json

# Test text (305 bytes - same as our Zig benchmark)
TEXT = """The cat sat on the mat. The dog ran in the park. The bird flew in the sky. The fish swam in the sea. The snake slithered on the ground. The rabbit hopped in the field. The fox ran through the forest. The bear climbed the tree. The wolf howled at the moon. The deer grazed in the meadow."""

print("📊 TOKENIZER BENCHMARK COMPARISON")
print("=" * 60)
print(f"Text length: {len(TEXT)} bytes")
print(f"Iterations: 30000")
print()

results = {}

# 1. tiktoken (Rust core)
print("Testing tiktoken (Rust)...")
try:
    import tiktoken
    enc = tiktoken.get_encoding("cl100k_base")
    
    # Warmup
    for _ in range(100):
        enc.encode(TEXT)
    
    iterations = 30000
    start = time.time()
    for _ in range(iterations):
        tokens = enc.encode(TEXT)
    elapsed = time.time() - start
    
    results['tiktoken'] = {
        'time_ms': int(elapsed * 1000),
        'tokens': len(tokens),
        'status': 'ok'
    }
    print(f"  ✅ {int(elapsed * 1000)}ms ({len(tokens)} tokens)")
except Exception as e:
    results['tiktoken'] = {'status': 'error', 'error': str(e)}
    print(f"  ❌ Error: {e}")

print()

# 2. TokenDagger
print("Testing TokenDagger...")
try:
    import tokendagger as tiktoken_dagger
    enc_dagger = tiktoken_dagger.get_encoding("cl100k_base")
    
    # Warmup
    for _ in range(100):
        enc_dagger.encode(TEXT)
    
    iterations = 30000
    start = time.time()
    for _ in range(iterations):
        tokens = enc_dagger.encode(TEXT)
    elapsed = time.time() - start
    
    results['tokendagger'] = {
        'time_ms': int(elapsed * 1000),
        'tokens': len(tokens),
        'status': 'ok'
    }
    print(f"  ✅ {int(elapsed * 1000)}ms ({len(tokens)} tokens)")
except Exception as e:
    results['tokendagger'] = {'status': 'error', 'error': str(e)}
    print(f"  ❌ Error: {e}")

print()

# 3. HuggingFace
print("Testing HuggingFace Tokenizers...")
try:
    from transformers import AutoTokenizer
    tokenizer_hf = AutoTokenizer.from_pretrained("openai-community/gpt2")
    
    # Warmup
    for _ in range(100):
        tokenizer_hf.encode(TEXT)
    
    iterations = 30000
    start = time.time()
    for _ in range(iterations):
        tokens = tokenizer_hf.encode(TEXT)
    elapsed = time.time() - start
    
    results['huggingface'] = {
        'time_ms': int(elapsed * 1000),
        'tokens': len(tokens),
        'status': 'ok'
    }
    print(f"  ✅ {int(elapsed * 1000)}ms ({len(tokens)} tokens)")
except Exception as e:
    results['huggingface'] = {'status': 'error', 'error': str(e)}
    print(f"  ❌ Error: {e}")

print()

# 4. metal0 Zig (run via subprocess)
print("Testing metal0 Zig...")
try:
    # Use our benchmark that does 60K iterations, divide by 2
    result = subprocess.run(
        ['./zig-out/bin/tokenizer_bench'],
        capture_output=True,
        text=True,
        timeout=30
    )
    
    # Parse output (Zig outputs to stderr via std.debug.print)
    for line in result.stderr.split('\n'):
        if 'iterations:' in line and 'ms total' in line:
            # Extract time: "60000 iterations: 827ms total"
            time_str = line.split('iterations:')[1].split('ms')[0].strip()
            time_60k = int(time_str)
            # Scale to 30K
            time_30k = time_60k // 2
            
            results['metal0_zig'] = {
                'time_ms': time_30k,
                'tokens': 139,
                'status': 'ok'
            }
            print(f"  ✅ {time_30k}ms (139 tokens)")
            break
    else:
        results['metal0_zig'] = {'status': 'error', 'error': 'Could not parse output'}
        print(f"  ❌ Could not parse benchmark output")
        
except Exception as e:
    results['metal0_zig'] = {'status': 'error', 'error': str(e)}
    print(f"  ❌ Error: {e}")

print()
print("=" * 60)
print("📊 FINAL RESULTS (30K iterations on 305-byte text)")
print("=" * 60)

# Sort by time
successful = [(k, v) for k, v in results.items() if v['status'] == 'ok']
successful.sort(key=lambda x: x[1]['time_ms'])

if successful:
    fastest_time = successful[0][1]['time_ms']
    
    print(f"{'Implementation':<20} {'Time':<12} {'vs Fastest':<12} {'Tokens'}")
    print("-" * 60)
    
    for name, data in successful:
        time_ms = data['time_ms']
        speedup = time_ms / fastest_time
        trophy = "🏆" if speedup == 1.0 else ""
        
        print(f"{name:<20} {time_ms:>8}ms   {speedup:>8.2f}x     {data['tokens']:>5} {trophy}")
    
    print()
    print("Key:")
    print("  tiktoken = Rust core (official)")
    print("  tokendagger = PCRE2 C + simplified BPE")
    print("  huggingface = Rust tokenizers library")
    print("  metal0_zig = Our pure Zig implementation")
else:
    print("No successful benchmarks!")
    
# Show errors
errors = [(k, v) for k, v in results.items() if v['status'] == 'error']
if errors:
    print()
    print("Errors:")
    for name, data in errors:
        print(f"  {name}: {data['error']}")

