package main

import (
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"
)

func main() {
	n := 1000
	if len(os.Args) > 1 {
		n, _ = strconv.Atoi(os.Args[1])
	}

	var wg sync.WaitGroup
	start := time.Now()

	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			// Just yield
		}()
	}

	wg.Wait()
	elapsed := time.Since(start).Seconds()
	throughput := float64(n) / elapsed

	fmt.Printf("%7d tasks in %6.3fs = %10.0f tasks/sec\n", n, elapsed, throughput)
}
