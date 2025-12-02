// CPU-Bound Benchmark: Fan-out/Fan-in (Go goroutines)
// Using SHA256 hashing for fair comparison with Python
package main

import (
	"crypto/sha256"
	"fmt"
	"strconv"
	"sync"
	"time"
)

const (
	NUM_TASKS     = 100
	WORK_PER_TASK = 10000 // 10K hash iterations per task
)

func worker(taskID int) int {
	h := sha256.New()
	for i := 0; i < WORK_PER_TASK; i++ {
		h.Write([]byte(strconv.Itoa(taskID + i)))
	}
	result := h.Sum(nil)
	return len(fmt.Sprintf("%x", result))
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

	fmt.Println("Benchmark: CPU-bound (SHA256)")
	fmt.Printf("Tasks: %d\n", NUM_TASKS)
	fmt.Printf("Work per task: %d hashes\n", WORK_PER_TASK)
	fmt.Printf("Total result: %d\n", total)
	fmt.Printf("Time: %.2fms\n", float64(elapsed.Nanoseconds())/1e6)
	fmt.Printf("Tasks/sec: %.0f\n", float64(NUM_TASKS)/(float64(elapsed.Nanoseconds())/1e9))
}
