// CPU-Bound Benchmark: Fan-out/Fan-in (Rust rayon)
use rayon::prelude::*;
use std::time::Instant;

const NUM_TASKS: i64 = 100;
const WORK_PER_TASK: usize = 20000000;  // 20M iterations per task

fn main() {
    // Runtime data - prevents compile-time optimization
    let data: Vec<i64> = (0..WORK_PER_TASK as i64).collect();

    let start = Instant::now();

    let total: i64 = (0..NUM_TASKS)
        .into_par_iter()
        .map(|task_id| {
            let mut result: i64 = 0;
            for &i in &data {
                result += i * task_id;
            }
            result
        })
        .sum();

    let elapsed = start.elapsed();

    println!("Benchmark: CPU-bound");
    println!("Tasks: {}", NUM_TASKS);
    println!("Work per task: {}", WORK_PER_TASK);
    println!("Total result: {}", total);
    println!("Time: {:.2}ms", elapsed.as_secs_f64() * 1000.0);
    println!("Tasks/sec: {:.0}", NUM_TASKS as f64 / elapsed.as_secs_f64());
}
