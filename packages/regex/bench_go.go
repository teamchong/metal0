package main

import (
	"fmt"
	"os"
	"regexp"
	"time"
)

type Benchmark struct {
	name    string
	pattern string
}

func loadData() string {
	data, err := os.ReadFile("bench_data.txt")
	if err != nil {
		panic(err)
	}
	return string(data)
}

func benchmarkPattern(name, pattern, text string, iterations int) {
	regex, err := regexp.Compile(pattern)
	if err != nil {
		fmt.Printf("%-20s COMPILE FAILED\n", name)
		return
	}

	// Warmup
	for i := 0; i < 100; i++ {
		regex.FindAllString(text, -1)
	}

	// Count matches
	matches := regex.FindAllString(text, -1)
	matchCount := len(matches)

	// Benchmark
	start := time.Now()
	for i := 0; i < iterations; i++ {
		regex.FindAllString(text, -1)
	}
	elapsed := time.Since(start)

	totalMs := elapsed.Seconds() * 1000
	avgUs := (elapsed.Seconds() / float64(iterations)) * 1_000_000

	fmt.Printf("%-20s %-10d %-12.2f %-12.2f\n", name, matchCount, avgUs, totalMs)
}

func main() {
	text := loadData()

	benchmarks := []Benchmark{
		{"Email", `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}`},
		{"URL", `https?://[^\s]+`},
		{"Phone", `\(\d{3}\)\s?\d{3}-\d{4}|\d{3}-\d{3}-\d{4}`},
		{"Digits", `\d+`},
		{"Word Boundary", `\b[a-z]{4,}\b`},
		{"Date ISO", `\d{4}-\d{2}-\d{2}`},
		{"IPv4", `\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b`},
		{"Hex Color", `#[0-9a-fA-F]{6}`},
		{"Version", `v?\d+\.\d+\.\d+`},
		{"Alphanumeric", `[a-z]+\d+`},
	}

	fmt.Println(string(make([]byte, 70)))
	for i := range make([]byte, 70) {
		fmt.Print("=")
		_ = i
	}
	fmt.Println()
	fmt.Println("Go Regex Benchmark (regexp package)")
	for i := range make([]byte, 70) {
		fmt.Print("=")
		_ = i
	}
	fmt.Println()
	fmt.Printf("%-20s %-10s %-12s %-12s\n", "Pattern", "Matches", "Avg (µs)", "Total (ms)")
	for i := range make([]byte, 70) {
		fmt.Print("-")
		_ = i
	}
	fmt.Println()

	for _, bench := range benchmarks {
		benchmarkPattern(bench.name, bench.pattern, text, 100000)
	}

	for i := range make([]byte, 70) {
		fmt.Print("-")
		_ = i
	}
	fmt.Println()
	for i := range make([]byte, 70) {
		fmt.Print("=")
		_ = i
	}
	fmt.Println()
}
