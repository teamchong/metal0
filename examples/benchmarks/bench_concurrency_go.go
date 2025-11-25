// Concurrency benchmark - Go goroutines
package main

import (
	"fmt"
	"sync"
	"time"
)

func worker(id int, wg *sync.WaitGroup, ch chan int) {
	defer wg.Done()

	// Simulate lightweight work
	time.Sleep(1 * time.Millisecond)

	ch <- id
}

func main() {
	numTasks := 10000 // 10k goroutines

	start := time.Now()

	var wg sync.WaitGroup
	ch := make(chan int, numTasks)

	// Spawn goroutines
	for i := 0; i < numTasks; i++ {
		wg.Add(1)
		go worker(i, &wg, ch)
	}

	// Wait for all to complete
	wg.Wait()
	close(ch)

	// Drain channel
	count := 0
	for range ch {
		count++
	}

	elapsed := time.Since(start)

	fmt.Printf("Completed %d tasks in %.3fs\n", numTasks, elapsed.Seconds())
	fmt.Printf("Tasks/sec: %.0f\n", float64(numTasks)/elapsed.Seconds())
	fmt.Printf("Avg latency: %.3fms\n", elapsed.Seconds()*1000/float64(numTasks))
}
