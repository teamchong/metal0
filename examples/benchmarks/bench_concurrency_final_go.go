// I/O Concurrency benchmark: 10k concurrent "network" operations
// Tests work-stealing and multi-core I/O handling
package main

import (
	"fmt"
	"sync"
	"time"
)

func fetchMock(id int, wg *sync.WaitGroup, results chan string) {
	defer wg.Done()
	// Mock network fetch with sleep (simulates I/O wait)
	time.Sleep(10 * time.Millisecond) // 10ms I/O delay
	results <- fmt.Sprintf("Response %d", id)
}

func main() {
	numRequests := 10000

	fmt.Printf("Starting %d concurrent mock requests...\n", numRequests)
	start := time.Now()

	var wg sync.WaitGroup
	results := make(chan string, numRequests)

	for i := 0; i < numRequests; i++ {
		wg.Add(1)
		go fetchMock(i, &wg, results)
	}
	wg.Wait()
	close(results)

	elapsed := time.Since(start)
	reqPerSec := float64(numRequests) / elapsed.Seconds()

	// Get first result
	firstResult := <-results
	for range results {
		// Drain channel
	}

	fmt.Printf("Completed %d requests in %.2fs\n", numRequests, elapsed.Seconds())
	fmt.Printf("Throughput: %.0f req/sec\n", reqPerSec)
	fmt.Printf("First result: %s\n", firstResult)
}
