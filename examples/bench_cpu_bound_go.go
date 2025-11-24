// CPU-bound benchmark: parallel fibonacci
// Tests multi-core parallelism
package main

import (
	"fmt"
	"sync"
	"time"
)

func fibSync(n int) int {
	// Synchronous fibonacci (CPU intensive)
	if n <= 1 {
		return n
	}
	return fibSync(n-1) + fibSync(n-2)
}

func fib(n int, wg *sync.WaitGroup, results chan int) {
	defer wg.Done()
	results <- fibSync(n)
}

func main() {
	// 100 parallel fib(30) computations
	numTasks := 100
	fibN := 30

	fmt.Printf("Computing %dx fib(%d) in parallel...\n", numTasks, fibN)
	start := time.Now()

	var wg sync.WaitGroup
	results := make(chan int, numTasks)

	for i := 0; i < numTasks; i++ {
		wg.Add(1)
		go fib(fibN, &wg, results)
	}
	wg.Wait()
	close(results)

	elapsed := time.Since(start)

	// Get one result
	result := <-results
	for range results {
		// Drain channel
	}

	fmt.Printf("Time: %.2fs\n", elapsed.Seconds())
	fmt.Printf("Result sample: fib(%d) = %d\n", fibN, result)
	fmt.Printf("Throughput: %.1f tasks/sec\n", float64(numTasks)/elapsed.Seconds())

	// Estimate core usage
	singleCoreTime := 0.1 * float64(numTasks) // ~10s
	speedup := singleCoreTime / elapsed.Seconds()
	fmt.Printf("Speedup vs single-core: %.1fx\n", speedup)
}
