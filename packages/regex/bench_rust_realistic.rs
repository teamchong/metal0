use regex::Regex;
use std::fs;
use std::time::Instant;

fn benchmark_pattern(name: &str, pattern: &str, text: &str, iterations: usize) {
    let re = Regex::new(pattern).unwrap();
    
    // Warmup
    let matches: Vec<_> = re.find_iter(text).collect();
    let match_count = matches.len();
    
    // Benchmark
    let start = Instant::now();
    for _ in 0..iterations {
        let _: Vec<_> = re.find_iter(text).collect();
    }
    let elapsed = start.elapsed();
    
    let total_ms = elapsed.as_secs_f64() * 1000.0;
    let avg_ms = total_ms / iterations as f64;
    
    println!("{:<20} {:<10} {:<12.2} {:<12.2} {:<12}",
        name, match_count, avg_ms, total_ms, iterations);
}

fn main() {
    let text = fs::read_to_string("bench_data_realistic.txt")
        .expect("Failed to read file");
    
    println!("Rust Regex Benchmark - REALISTIC DATA");
    println!("Data size: {} bytes ({:.2} MB)", text.len(), text.len() as f64 / (1024.0 * 1024.0));
    println!("Pattern              Matches    Avg (ms)    Total (ms)   Iterations  ");
    println!("--------------------------------------------------------------------------------");
    
    benchmark_pattern("Email", r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}", &text, 1000);
    benchmark_pattern("URL", r"https?://[^\s]+", &text, 500);
    benchmark_pattern("Digits", r"[0-9]+", &text, 100);
    benchmark_pattern("Word Boundary", r"\b[a-z]{4,}\b", &text, 100);
    benchmark_pattern("Date ISO", r"[0-9]{4}-[0-9]{2}-[0-9]{2}", &text, 1000);
}
