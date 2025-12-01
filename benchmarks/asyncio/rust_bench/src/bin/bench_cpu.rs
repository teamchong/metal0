// CPU-Bound Benchmark: Fan-out/Fan-in (Rust rayon)
use rayon::prelude::*;
use std::time::Instant;

const NUM_TASKS: i64 = 1000;
const WORK_PER_TASK: i64 = 10000;

fn worker(task_id: i64) -> i64 {
    let mut result: i64 = 0;
    for i in 0..WORK_PER_TASK {
        result += i * task_id;
    }
    result
}

fn main() {
    let start = Instant::now();

    let total: i64 = (0..NUM_TASKS)
        .into_par_iter()
        .map(worker)
        .sum();

    let elapsed = start.elapsed();

    println!("Benchmark: CPU-bound");
    println!("Tasks: {}", NUM_TASKS);
    println!("Work per task: {}", WORK_PER_TASK);
    println!("Total result: {}", total);
    println!("Time: {:.2}ms", elapsed.as_secs_f64() * 1000.0);
    println!("Tasks/sec: {:.0}", NUM_TASKS as f64 / elapsed.as_secs_f64());
}
