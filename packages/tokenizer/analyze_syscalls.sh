#!/bin/bash

echo "=== metal0 Tokenizer Syscall Analysis ==="
echo ""
echo "Running benchmark 3 times to get average..."
echo ""

total_real=0
total_user=0
total_sys=0
total_reclaims=0
total_faults=0
total_vol_ctx=0
total_invol_ctx=0

for i in 1 2 3; do
    echo "Run $i..."
    OUTPUT=$(/usr/bin/time -l ./zig-out/bin/tokenizer_bench 2>&1)
    
    real=$(echo "$OUTPUT" | grep real | awk '{print $1}')
    user=$(echo "$OUTPUT" | grep real | awk '{print $3}')
    sys=$(echo "$OUTPUT" | grep real | awk '{print $5}')
    reclaims=$(echo "$OUTPUT" | grep "page reclaims" | awk '{print $1}')
    faults=$(echo "$OUTPUT" | grep "page faults" | awk '{print $1}')
    vol_ctx=$(echo "$OUTPUT" | grep "voluntary context" | awk '{print $1}')
    invol_ctx=$(echo "$OUTPUT" | grep "involuntary context" | awk '{print $1}')
    
    total_real=$(echo "$total_real + $real" | bc)
    total_user=$(echo "$total_user + $user" | bc)
    total_sys=$(echo "$total_sys + $sys" | bc)
    total_reclaims=$(( total_reclaims + reclaims ))
    total_faults=$(( total_faults + faults ))
    total_vol_ctx=$(( total_vol_ctx + vol_ctx ))
    total_invol_ctx=$(( total_invol_ctx + invol_ctx ))
done

echo ""
echo "=== Average Results (3 runs) ==="
echo "Real time: $(echo "scale=2; $total_real / 3" | bc)s"
echo "User time: $(echo "scale=2; $total_user / 3" | bc)s"
echo "System time: $(echo "scale=2; $total_sys / 3" | bc)s"
echo "Page reclaims: $(( total_reclaims / 3 ))"
echo "Page faults: $(( total_faults / 3 ))"
echo "Voluntary context switches: $(( total_vol_ctx / 3 ))"
echo "Involuntary context switches: $(( total_invol_ctx / 3 ))"

