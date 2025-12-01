// CPU-Bound Benchmark: Fan-out/Fan-in (Go goroutines)
package main

import (
	"fmt"
	"sync"
	"time"
)

const (
	NUM_TASKS     = 1000
	WORK_PER_TASK = 10000
)

func worker(taskID int) int64 {
	var result int64 = 0
	for i := 0; i < WORK_PER_TASK; i++ {
		result += int64(i * taskID)
	}
	return result
}

func main() {
	start := time.Now()

	results := make(chan int64, NUM_TASKS)
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

	var total int64 = 0
	for result := range results {
		total += result
	}

	elapsed := time.Since(start)

	fmt.Println("Benchmark: CPU-bound")
	fmt.Printf("Tasks: %d\n", NUM_TASKS)
	fmt.Printf("Work per task: %d\n", WORK_PER_TASK)
	fmt.Printf("Total result: %d\n", total)
	fmt.Printf("Time: %.2fms\n", float64(elapsed.Nanoseconds())/1e6)
	fmt.Printf("Tasks/sec: %.0f\n", float64(NUM_TASKS)/(float64(elapsed.Nanoseconds())/1e9))
}
