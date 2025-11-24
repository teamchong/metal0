package main
import "time"
import "fmt"

func handler() string {
    return `{"message": "Hello, World!", "status": "ok"}`
}

func main() {
    start := time.Now()
    for i := 0; i < 1000000; i++ {
        _ = handler()
    }
    elapsed := time.Since(start).Seconds()
    fmt.Printf("%.3fs, %.0f req/s\n", elapsed, 1000000/elapsed)
}
