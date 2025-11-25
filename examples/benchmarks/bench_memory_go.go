// Memory benchmark: 1M sleeping goroutines
// Tests memory overhead per goroutine
package main

import (
	"fmt"
	"runtime"
	"time"
)

func sleepTask(duration time.Duration, done chan bool) {
	// Sleep for specified duration
	time.Sleep(duration)
	done <- true
}

func main() {
	numTasks := 1_000_000
	sleepDuration := 3600 * time.Second // 1 hour (won't actually wait)

	fmt.Printf("Creating %d sleeping goroutines...\n", numTasks)

	// Measure initial memory
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	initialAlloc := m.Alloc / (1024 * 1024) // MB

	start := time.Now()

	// Create all goroutines
	done := make(chan bool, numTasks)
	for i := 0; i < numTasks; i++ {
		go sleepTask(sleepDuration, done)

		if i%100000 == 0 && i > 0 {
			fmt.Printf("  Created %d goroutines...\n", i)
			runtime.Gosched() // yield to let goroutines start
		}
	}

	creationTime := time.Since(start)

	// Let goroutines actually start
	time.Sleep(1 * time.Second)

	// Force GC to get accurate numbers
	runtime.GC()

	// Measure final memory
	runtime.ReadMemStats(&m)
	finalAlloc := m.Alloc / (1024 * 1024) // MB
	memoryUsed := finalAlloc - initialAlloc
	bytesPerTask := (memoryUsed * 1024 * 1024) / uint64(numTasks)

	fmt.Printf("\nResults:\n")
	fmt.Printf("  Goroutines created: %d\n", numTasks)
	fmt.Printf("  Creation time: %.2fs\n", creationTime.Seconds())
	fmt.Printf("  Memory used: %dMB\n", memoryUsed)
	fmt.Printf("  Per-goroutine overhead: %d bytes\n", bytesPerTask)
	fmt.Printf("  Creation rate: %.0f goroutines/sec\n", float64(numTasks)/creationTime.Seconds())

	// Note: We don't wait for goroutines to finish
	// They'll be cleaned up when program exits
}
