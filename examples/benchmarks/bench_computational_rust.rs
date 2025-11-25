use std::time::Instant;

fn handler() -> &'static str {
    r#"{"message": "Hello, World!", "status": "ok"}"#
}

fn main() {
    let start = Instant::now();
    for _ in 0..1_000_000 {
        let _ = handler();
    }
    let elapsed = start.elapsed().as_secs_f64();
    println!("{:.3}s, {:.0} req/s", elapsed, 1_000_000.0 / elapsed);
}
