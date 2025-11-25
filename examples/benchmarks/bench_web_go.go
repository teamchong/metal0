// HTTP Server benchmark
// Run: go run examples/bench_web_go.go &
// Test: wrk -t4 -c100 -d10s http://localhost:8080/json
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
)

type Message struct {
	Message string `json:"message"`
}

func jsonHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(Message{Message: "Hello, World!"})
}

func main() {
	http.HandleFunc("/json", jsonHandler)

	fmt.Println("Go HTTP server listening on :8080")
	fmt.Println("Test with: wrk -t4 -c100 -d10s http://localhost:8080/json")

	log.Fatal(http.ListenAndServe(":8080", nil))
}
