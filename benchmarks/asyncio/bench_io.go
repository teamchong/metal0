// I/O-Bound Benchmark: Concurrent Sleep (Go goroutines)
package main

import (
	"fmt"
	"sync"
	"time"
)

const (
	NUM_TASKS = 10000
	SLEEP_MS  = 1
)

func worker(taskID int) int {
	time.Sleep(SLEEP_MS * time.Millisecond)
	return taskID
}

func main() {
	start := time.Now()

	results := make(chan int, NUM_TASKS)
	var wg sync.WaitGroup

	for i := 0; i < NUM_TASKS; i++ {
		wg.Add(1)
		go func(taskID int) {
			defer wg.Done()
			results <- worker(taskID)
		}(i)
	}

	go func() {
		wg.Wait()
		close(results)
	}()

	var total int = 0
	for result := range results {
		total += result
	}

	elapsed := time.Since(start)

	fmt.Println("Benchmark: I/O-bound")
	fmt.Printf("Tasks: %d\n", NUM_TASKS)
	fmt.Printf("Sleep per task: %dms\n", SLEEP_MS)
	fmt.Printf("Total result: %d\n", total)
	fmt.Printf("Time: %.2fms\n", float64(elapsed.Nanoseconds())/1e6)
	fmt.Printf("Tasks/sec: %.0f\n", float64(NUM_TASKS)/(float64(elapsed.Nanoseconds())/1e9))
	fmt.Printf("Sequential would be: %dms\n", NUM_TASKS*SLEEP_MS)
	fmt.Printf("Concurrency factor: %.0fx\n", float64(NUM_TASKS*SLEEP_MS)/(float64(elapsed.Nanoseconds())/1e6))
}
