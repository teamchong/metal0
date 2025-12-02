// CPU-Bound Benchmark: Fan-out/Fan-in (Rust rayon)
// Using SHA256 hashing for fair comparison with Python
use rayon::prelude::*;
use sha2::{Sha256, Digest};
use std::time::Instant;

const NUM_TASKS: i64 = 100;
const WORK_PER_TASK: i64 = 10000; // 10K hash iterations per task

fn main() {
    let start = Instant::now();

    let total: usize = (0..NUM_TASKS)
        .into_par_iter()
        .map(|task_id| {
            let mut hasher = Sha256::new();
            for i in 0..WORK_PER_TASK {
                hasher.update(format!("{}", task_id + i).as_bytes());
            }
            let result = hasher.finalize();
            format!("{:x}", result).len()
        })
        .sum();

    let elapsed = start.elapsed();

    println!("Benchmark: CPU-bound (SHA256)");
    println!("Tasks: {}", NUM_TASKS);
    println!("Work per task: {} hashes", WORK_PER_TASK);
    println!("Total result: {}", total);
    println!("Time: {:.2}ms", elapsed.as_secs_f64() * 1000.0);
    println!("Tasks/sec: {:.0}", NUM_TASKS as f64 / elapsed.as_secs_f64());
}
