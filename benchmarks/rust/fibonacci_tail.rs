fn fib_tail(n: u64, a: u64, b: u64) -> u64 {
    if n == 0 { a } else { fib_tail(n - 1, b, a + b) }
}

fn main() {
    let mut result = 0u64;
    for _ in 0..10000 {
        result = fib_tail(10000, 0, 1);
    }
    println!("{}", result);
}
