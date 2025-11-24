// Benchmark Go goroutines scheduler
package main

import (
	"fmt"
	"runtime"
	"sync"
	"time"
)

func worker(n int, wg *sync.WaitGroup) {
	defer wg.Done()

	// Yield 100 times
	for i := 0; i < 100; i++ {
		runtime.Gosched()
	}
}

func main() {
	start := time.Now()

	// Spawn 100,000 goroutines
	var wg sync.WaitGroup
	for i := 0; i < 100000; i++ {
		wg.Add(1)
		go worker(i, &wg)
	}

	wg.Wait()
	elapsed := time.Since(start)

	fmt.Printf("Tasks: 100,000\n")
	fmt.Printf("Time: %.3fs\n", elapsed.Seconds())
	fmt.Printf("Tasks/sec: %.0f\n", 100000.0/elapsed.Seconds())
}
