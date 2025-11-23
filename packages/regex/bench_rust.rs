use regex::Regex;
use std::fs;
use std::time::Instant;

struct Benchmark {
    name: &'static str,
    pattern: &'static str,
}

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
        "{:<20} {:<10} {:<12.2} {:<12.2}",
        name, match_count, avg_us, total_ms
    );
}

fn main() {
    let text = load_data();

    let benchmarks = vec![
        Benchmark {
            name: "Email",
            pattern: r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}",
        },
        Benchmark {
            name: "URL",
            pattern: r"https?://[^\s]+",
        },
        Benchmark {
            name: "Phone",
            pattern: r"\(\d{3}\)\s?\d{3}-\d{4}|\d{3}-\d{3}-\d{4}",
        },
        Benchmark {
            name: "Digits",
            pattern: r"\d+",
        },
        Benchmark {
            name: "Word Boundary",
            pattern: r"\b[a-z]{4,}\b",
        },
        Benchmark {
            name: "Date ISO",
            pattern: r"\d{4}-\d{2}-\d{2}",
        },
        Benchmark {
            name: "IPv4",
            pattern: r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b",
        },
        Benchmark {
            name: "Hex Color",
            pattern: r"#[0-9a-fA-F]{6}",
        },
        Benchmark {
            name: "Version",
            pattern: r"v?\d+\.\d+\.\d+",
        },
        Benchmark {
            name: "Alphanumeric",
            pattern: r"[a-z]+\d+",
        },
    ];

    println!("{}", "=".repeat(70));
    println!("Rust Regex Benchmark (regex crate)");
    println!("{}", "=".repeat(70));
    println!("{:<20} {:<10} {:<12} {:<12}", "Pattern", "Matches", "Avg (µs)", "Total (ms)");
    println!("{}", "-".repeat(70));

    for bench in benchmarks {
        benchmark_pattern(bench.name, bench.pattern, &text, 10000);
    }

    println!("{}", "-".repeat(70));
    println!("{}", "=".repeat(70));
}
