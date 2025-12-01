// I/O-Bound Benchmark: Concurrent Sleep (Rust tokio)
use std::time::Instant;
use tokio::time::{sleep, Duration};

const NUM_TASKS: i64 = 10000;
const SLEEP_MS: u64 = 1;

async fn worker(task_id: i64) -> i64 {
    sleep(Duration::from_millis(SLEEP_MS)).await;
    task_id
}

#[tokio::main]
async fn main() {
    let start = Instant::now();

    // Spawn all tasks
    let handles: Vec<_> = (0..NUM_TASKS)
        .map(|i| tokio::spawn(worker(i)))
        .collect();

    // Collect results
    let mut total: i64 = 0;
    for handle in handles {
        total += handle.await.unwrap();
    }

    let elapsed = start.elapsed();

    println!("Benchmark: I/O-bound");
    println!("Tasks: {}", NUM_TASKS);
    println!("Sleep per task: {}ms", SLEEP_MS);
    println!("Total result: {}", total);
    println!("Time: {:.2}ms", elapsed.as_secs_f64() * 1000.0);
    println!("Tasks/sec: {:.0}", NUM_TASKS as f64 / elapsed.as_secs_f64());
    println!("Sequential would be: {}ms", NUM_TASKS as u64 * SLEEP_MS);
    println!("Concurrency factor: {:.0}x", (NUM_TASKS as u64 * SLEEP_MS) as f64 / (elapsed.as_secs_f64() * 1000.0));
}
