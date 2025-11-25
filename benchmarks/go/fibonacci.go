package main

import "fmt"

func fibonacci(n int) int {
	if n <= 1 {
		return n
	}
	return fibonacci(n-1) + fibonacci(n-2)
}

func main() {
	// Benchmark with fibonacci(45) - ensures ~60 seconds runtime comparison
	result := fibonacci(45)
	fmt.Println(result)
}
