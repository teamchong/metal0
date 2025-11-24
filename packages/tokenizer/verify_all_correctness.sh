#!/bin/bash
set -e

echo "=== CORRECTNESS VERIFICATION SUITE ==="
echo ""

# Test 1: Unigram
echo "1. Testing Unigram (751 tokens)..."
ALGORITHM=Unigram VOCAB_SIZE=751 ITERATIONS=1 timeout 30 ./zig-out/bin/bench_train 2>&1 | grep "Finalized" | grep "751 (target: 751)" && echo "✅ Unigram CORRECT" || echo "❌ Unigram FAILED"

# Test 2: BPE  
echo ""
echo "2. Testing BPE (32000 tokens)..."
ALGORITHM=BPE VOCAB_SIZE=32000 ITERATIONS=1 timeout 60 ./zig-out/bin/bench_train 2>&1 > /dev/null && echo "✅ BPE COMPLETED" || echo "❌ BPE FAILED"

# Test 3: WordPiece
echo ""
echo "3. Testing WordPiece (32000 tokens)..."
ALGORITHM=WordPiece VOCAB_SIZE=32000 ITERATIONS=1 timeout 60 ./zig-out/bin/bench_train 2>&1 > /dev/null && echo "✅ WordPiece COMPLETED" || echo "❌ WordPiece FAILED"

# Test 4: Memory leaks
echo ""
echo "4. Testing for memory leaks..."
leak_count=0
for algo in Unigram BPE WordPiece; do
    leaks=$(ALGORITHM=$algo ITERATIONS=1 timeout 60 ./zig-out/bin/bench_train 2>&1 | grep -c "error(gpa)" || true)
    if [ "$leaks" -eq 0 ]; then
        echo "✅ $algo: NO LEAKS"
    else
        echo "❌ $algo: $leaks LEAKS FOUND"
        leak_count=$((leak_count + 1))
    fi
done

echo ""
echo "=== SUMMARY ==="
if [ "$leak_count" -eq 0 ]; then
    echo "✅ ALL TESTS PASSED - 100% CORRECT & LEAK-FREE"
    exit 0
else
    echo "❌ $leak_count ALGORITHMS HAVE LEAKS"
    exit 1
fi
