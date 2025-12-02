// CPU-Bound Benchmark: Parallel Scaling Test (Go goroutines)
// Measures true parallelism: Sequential vs Parallel speedup
package main

import (
	"crypto/sha256"
	"fmt"
	"strconv"
	"sync"
	"time"
)

const (
	NUM_WORKERS     = 8
	WORK_PER_WORKER = 50000 // 50K hash iterations per worker
)

func doWork(workerID int, iterations int) int {
	h := sha256.New()
	for i := 0; i < iterations; i++ {
		h.Write([]byte(strconv.Itoa(workerID + i)))
	}
	return len(fmt.Sprintf("%x", h.Sum(nil)))
}

func main() {
	// Sequential: 1 worker does ALL work
	seqStart := time.Now()
	seqTotal := doWork(0, NUM_WORKERS*WORK_PER_WORKER)
	seqTime := time.Since(seqStart)
	_ = seqTotal

	// Parallel: N workers split work
	parStart := time.Now()
	results := make(chan int, NUM_WORKERS)
	var wg sync.WaitGroup

	for i := 0; i < NUM_WORKERS; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			results <- doWork(workerID, WORK_PER_WORKER)
		}(i)
	}

	go func() {
		wg.Wait()
		close(results)
	}()

	parTotal := 0
	for result := range results {
		parTotal += result
	}
	parTime := time.Since(parStart)
	_ = parTotal

	speedup := float64(seqTime.Nanoseconds()) / float64(parTime.Nanoseconds())
	efficiency := (speedup / float64(NUM_WORKERS)) * 100

	fmt.Println("Benchmark: Parallel Scaling (SHA256)")
	fmt.Printf("Workers: %d\n", NUM_WORKERS)
	fmt.Printf("Work/worker: %d hashes\n", WORK_PER_WORKER)
	fmt.Printf("Sequential: %.2fms\n", float64(seqTime.Nanoseconds())/1e6)
	fmt.Printf("Parallel:   %.2fms\n", float64(parTime.Nanoseconds())/1e6)
	fmt.Printf("Speedup:    %.2fx\n", speedup)
	fmt.Printf("Efficiency: %.0f%%\n", efficiency)
}
