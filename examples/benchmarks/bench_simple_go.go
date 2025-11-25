// Simple benchmark: 10k noop goroutines
// Tests task creation/scheduling overhead
package main

import (
	"fmt"
	"sync"
	"time"
)

func noop(wg *sync.WaitGroup) {
	// Empty task - just overhead
	wg.Done()
}

func main() {
	start := time.Now()

	var wg sync.WaitGroup
	for i := 0; i < 10000; i++ {
		wg.Add(1)
		go noop(&wg)
	}
	wg.Wait()

	elapsed := time.Since(start)
	fmt.Printf("Spawned 10k goroutines in %.2fms\n", float64(elapsed.Microseconds())/1000.0)
	fmt.Printf("Throughput: %.0f goroutines/sec\n", 10000.0/elapsed.Seconds())
}
