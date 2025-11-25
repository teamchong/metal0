// Context switch benchmark: rapid yield/resume
// Tests scheduler overhead
package main

import (
	"fmt"
	"runtime"
	"sync"
	"time"
)

func ping(n int, wg *sync.WaitGroup) {
	defer wg.Done()
	// Yield n times
	for i := 0; i < n; i++ {
		runtime.Gosched() // yield to scheduler
	}
}

func main() {
	numTasks := 10
	yieldsPerTask := 100000
	totalSwitches := numTasks * yieldsPerTask

	start := time.Now()

	var wg sync.WaitGroup
	for i := 0; i < numTasks; i++ {
		wg.Add(1)
		go ping(yieldsPerTask, &wg)
	}
	wg.Wait()

	elapsed := time.Since(start)
	nsPerSwitch := float64(elapsed.Nanoseconds()) / float64(totalSwitches)

	fmt.Printf("Total context switches: %d\n", totalSwitches)
	fmt.Printf("Time: %.3fs\n", elapsed.Seconds())
	fmt.Printf("Per-switch: %.0fns\n", nsPerSwitch)
	fmt.Printf("Throughput: %.0f switches/sec\n", float64(totalSwitches)/elapsed.Seconds())
}
