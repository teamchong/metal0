package main

import "fmt"

func fibTail(n, a, b uint64) uint64 {
    if n == 0 { return a }
    return fibTail(n-1, b, a+b)
}

func main() {
    var result uint64
    for i := 0; i < 10000; i++ {
        result = fibTail(10000, 0, 1)
    }
    fmt.Println(result)
}
