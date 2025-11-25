package main

import (
	"fmt"
	"sort"
	"sync"
	"time"
)

func main() {
	var latencies []float64
	var mu sync.Mutex
	var wg sync.WaitGroup

	for i := 0; i < 10000; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			start := time.Now()
			time.Sleep(1 * time.Millisecond)
			elapsed := float64(time.Since(start).Microseconds()) / 1000.0

			mu.Lock()
			latencies = append(latencies, elapsed)
			mu.Unlock()
		}()
	}

	wg.Wait()

	sort.Float64s(latencies)
	n := len(latencies)

	p50 := latencies[n/2]
	p95 := latencies[int(float64(n)*0.95)]
	p99 := latencies[int(float64(n)*0.99)]

	fmt.Printf("Latency Distribution (10k tasks):\n")
	fmt.Printf("  p50: %.2fms\n", p50)
	fmt.Printf("  p95: %.2fms\n", p95)
	fmt.Printf("  p99: %.2fms\n", p99)
}
