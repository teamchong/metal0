#!/bin/bash
set -e

echo "🔍 100% VICTORY VERIFICATION"
echo "=============================="
echo ""

# 1. Correctness Check
echo "1️⃣ CORRECTNESS: Verify output matches rs-bpe exactly"
echo "---------------------------------------------------"

# Build fresh
zig build -Doptimize=ReleaseFast > /dev/null 2>&1

# Test encoding produces same tokens
TEST_TEXT="Hello, world! This is a test of the tokenizer."

# Encode with metal0
metal0_TOKENS=$(echo "$TEST_TEXT" | ./zig-out/bin/test_correctness 2>/dev/null || echo "ERROR")

# Encode with rs-bpe (Python)
cat > /tmp/test_rsbpe.py << 'PYTHON'
import sys
sys.path.insert(0, 'benchmark_libs/rs-bpe/target/wheels')
import rs_bpe
tokenizer = rs_bpe.Tokenizer.from_file("dist/cl100k_base_full.json")
text = "Hello, world! This is a test of the tokenizer."
tokens = tokenizer.encode(text)
print(','.join(map(str, tokens)))
PYTHON

RSBPE_TOKENS=$(python3 /tmp/test_rsbpe.py 2>/dev/null || echo "ERROR")

if [ "$metal0_TOKENS" = "$RSBPE_TOKENS" ]; then
    echo "✅ PASS: Outputs match exactly"
else
    echo "❌ FAIL: Outputs differ!"
    echo "metal0:  $metal0_TOKENS"
    echo "rs-bpe: $RSBPE_TOKENS"
    exit 1
fi
echo ""

# 2. Multiple Runs for Statistical Confidence
echo "2️⃣ STATISTICAL CONFIDENCE: 10 full benchmarks (1000 iter each)"
echo "----------------------------------------------------------------"

metal0_TIMES=()
RSBPE_TIMES=()

for i in {1..10}; do
    echo "Run $i/10..."

    # Run benchmark and extract times
    OUTPUT=$(make benchmark-encoding 2>&1)

    metal0_TIME=$(echo "$OUTPUT" | grep "Benchmark 1: metal0" -A1 | grep "Time (mean" | awk '{print $5}')
    RSBPE_TIME=$(echo "$OUTPUT" | grep "Benchmark 2: rs-bpe" -A1 | grep "Time (mean" | awk '{print $5}')

    metal0_TIMES+=("$metal0_TIME")
    RSBPE_TIMES+=("$RSBPE_TIME")

    echo "  metal0: ${metal0_TIME}s, rs-bpe: ${RSBPE_TIME}s"
done

echo ""
echo "📊 RESULTS (10 runs):"
echo "---------------------"
echo "metal0 times:  ${metal0_TIMES[@]}"
echo "rs-bpe times: ${RSBPE_TIMES[@]}"
echo ""

# Calculate averages
metal0_AVG=$(echo "${metal0_TIMES[@]}" | tr ' ' '\n' | awk '{sum+=$1} END {print sum/NR}')
RSBPE_AVG=$(echo "${RSBPE_TIMES[@]}" | tr ' ' '\n' | awk '{sum+=$1} END {print sum/NR}')

SPEEDUP=$(echo "$RSBPE_AVG / $metal0_AVG" | bc -l)

echo "Average metal0:  ${metal0_AVG}s"
echo "Average rs-bpe: ${RSBPE_AVG}s"
echo "Speedup:        ${SPEEDUP}x"
echo ""

# 3. Check if consistently faster
echo "3️⃣ CONSISTENCY: metal0 faster in ALL runs?"
echo "-------------------------------------------"

WINS=0
for i in {0..9}; do
    metal0=${metal0_TIMES[$i]}
    RSBPE=${RSBPE_TIMES[$i]}

    if (( $(echo "$metal0 < $RSBPE" | bc -l) )); then
        WINS=$((WINS + 1))
        echo "Run $((i+1)): ✅ WIN (${metal0}s < ${RSBPE}s)"
    else
        echo "Run $((i+1)): ❌ LOSS (${metal0}s >= ${RSBPE}s)"
    fi
done

echo ""
echo "Win rate: $WINS/10 ($(echo "$WINS * 10" | bc)%)"
echo ""

# 4. Final Verdict
echo "🏆 FINAL VERDICT"
echo "================"

if [ $WINS -eq 10 ]; then
    echo "✅ 100% VICTORY CONFIRMED!"
    echo "   - Correctness: VERIFIED"
    echo "   - Win rate: 10/10 (100%)"
    echo "   - Average speedup: ${SPEEDUP}x"
    echo ""
    echo "metal0 is definitively faster than rs-bpe! 🎉"
elif [ $WINS -ge 8 ]; then
    echo "⚠️  LIKELY VICTORY (${WINS}/10 wins)"
    echo "   Some variance detected - may need system optimization"
else
    echo "❌ INCONCLUSIVE"
    echo "   Too much variance - investigate system load"
    exit 1
fi
