// Rust Parallel Scaling Benchmark
// Measures true parallelism: Sequential vs Parallel speedup
use rayon::prelude::*;
use sha2::{Sha256, Digest};
use std::time::Instant;

const NUM_WORKERS: usize = 8;
const WORK_PER_WORKER: usize = 50000; // 50K hash iterations per worker

fn do_work(worker_id: usize, iterations: usize) -> usize {
    let mut hasher = Sha256::new();
    for i in 0..iterations {
        hasher.update((worker_id + i).to_string().as_bytes());
    }
    let result = hasher.finalize();
    format!("{:x}", result).len()
}

fn main() {
    // Sequential: 1 worker does ALL work
    let seq_start = Instant::now();
    let _seq_total = do_work(0, NUM_WORKERS * WORK_PER_WORKER);
    let seq_time = seq_start.elapsed();

    // Parallel: N workers split work
    let par_start = Instant::now();
    let _par_total: usize = (0..NUM_WORKERS)
        .into_par_iter()
        .map(|id| do_work(id, WORK_PER_WORKER))
        .sum();
    let par_time = par_start.elapsed();

    let speedup = seq_time.as_secs_f64() / par_time.as_secs_f64();
    let efficiency = (speedup / NUM_WORKERS as f64) * 100.0;

    println!("Benchmark: Parallel Scaling (SHA256)");
    println!("Workers: {}", NUM_WORKERS);
    println!("Work/worker: {} hashes", WORK_PER_WORKER);
    println!("Sequential: {:.2}ms", seq_time.as_secs_f64() * 1000.0);
    println!("Parallel:   {:.2}ms", par_time.as_secs_f64() * 1000.0);
    println!("Speedup:    {:.2}x", speedup);
    println!("Efficiency: {:.0}%", efficiency);
}
