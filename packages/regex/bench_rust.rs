use regex::Regex;
use std::fs;
use std::time::Instant;

fn load_data() -> String {
    fs::read_to_string("bench_data.txt").expect("Failed to read bench_data.txt")
}

fn benchmark_pattern(name: &str, pattern: &str, text: &str, iterations: usize) {
    let regex = match Regex::new(pattern) {
        Ok(r) => r,
        Err(_) => {
            println!("{:<20} COMPILE FAILED", name);
            return;
        }
    };

    // Warmup
    for _ in 0..100 {
        let _: Vec<_> = regex.find_iter(text).collect();
    }

    // Count matches
    let match_count = regex.find_iter(text).count();

    // Benchmark
    let start = Instant::now();
    for _ in 0..iterations {
        let _: Vec<_> = regex.find_iter(text).collect();
    }
    let elapsed = start.elapsed();

    let total_ms = elapsed.as_secs_f64() * 1000.0;
    let avg_us = (elapsed.as_secs_f64() / iterations as f64) * 1_000_000.0;

    println!(
        "{:<20} {:<10} {:<12.2} {:<12.2} {:<12}",
        name, match_count, avg_us, total_ms, iterations
    );
}

fn main() {
    let text = load_data();

    println!("{}", "=".repeat(70));
    println!("Rust Regex Benchmark (variable iterations for accurate measurements)");
    println!("{}", "=".repeat(70));
    println!("{:<20} {:<10} {:<12} {:<12} {:<12}", "Pattern", "Matches", "Avg (µs)", "Total (ms)", "Iterations");
    println!("{}", "-".repeat(80));

    // Match PyAOT iteration counts per pattern
    benchmark_pattern("Email", r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}", &text, 1000000);
    benchmark_pattern("URL", r"https?://[^\s]+", &text, 1000000);
    benchmark_pattern("Digits", r"\d+", &text, 1000000);
    benchmark_pattern("Word Boundary", r"\b[a-z]{4,}\b", &text, 100000);
    benchmark_pattern("Date ISO", r"\d{4}-\d{2}-\d{2}", &text, 1000000);

    println!("{}", "-".repeat(70));
    println!("{}", "=".repeat(70));
}
