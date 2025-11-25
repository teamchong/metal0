fn fibonacci(n: i32) -> i32 {
    if n <= 1 {
        return n;
    }
    fibonacci(n - 1) + fibonacci(n - 2)
}

fn main() {
    // Benchmark with fibonacci(45) - ensures ~60 seconds runtime comparison
    let result = fibonacci(45);
    println!("{}", result);
}
