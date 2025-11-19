/// Minimal Rust BPE for comparison
/// Simplified from nanochat's rustbpe

use std::collections::HashMap;
use std::time::Instant;
use ahash::AHashMap;
use rayon::prelude::*;

type Pair = (u32, u32);

#[derive(Clone)]
struct Word {
    ids: Vec<u32>,
}

impl Word {
    fn pairs(&self) -> impl Iterator<Item = Pair> + '_ {
        self.ids.windows(2).map(|w| (w[0], w[1]))
    }

    fn merge_pair(&mut self, pair: Pair, new_id: u32) {
        let (a, b) = pair;
        let n = self.ids.len();
        if n < 2 {
            return;
        }

        let mut out = Vec::with_capacity(n);
        let mut i = 0;
        while i < n {
            if i + 1 < n && self.ids[i] == a && self.ids[i + 1] == b {
                out.push(new_id);
                i += 2;
            } else {
                out.push(self.ids[i]);
                i += 1;
            }
        }
        self.ids = out;
    }
}

fn count_pairs_parallel(words: &[Word], counts: &[i32]) -> AHashMap<Pair, i32> {
    words
        .par_iter()
        .enumerate()
        .map(|(i, w)| {
            let mut local_pc = AHashMap::new();
            if w.ids.len() >= 2 && counts[i] != 0 {
                for pair in w.pairs() {
                    *local_pc.entry(pair).or_default() += counts[i];
                }
            }
            local_pc
        })
        .reduce(
            || AHashMap::new(),
            |mut acc, pc| {
                for (k, v) in pc {
                    *acc.entry(k).or_default() += v;
                }
                acc
            },
        )
}

fn main() {
    println!("\n🦀 Rust rustbpe Benchmark");
    println!("{}", "=".repeat(60));
    println!();

    // Benchmark: Training
    println!("Benchmark: BPE Training");
    println!("{}", "-".repeat(40));

    let base_texts = vec![
        "Hello world! This is a test.",
        "The quick brown fox jumps over the lazy dog.",
        "Machine learning and natural language processing.",
        "Byte pair encoding is a text tokenization method.",
        "This is a longer text to make training more interesting.",
        "Neural networks learn from large amounts of training data.",
        "Tokenization breaks text into smaller units called tokens.",
        "Python is a popular programming language for data science.",
        "Deep learning models require significant computational resources.",
        "Natural language understanding is a challenging AI problem.",
        "Transformers revolutionized the field of NLP in recent years.",
        "GPT models demonstrate impressive text generation capabilities.",
        "Byte pair encoding creates subword vocabularies efficiently.",
        "Machine translation systems bridge communication across languages.",
        "Sentiment analysis determines emotional tone in text.",
    ];

    // Quick benchmark for hyperfine: 500 texts
    let training_texts: Vec<&str> = base_texts.into_iter().cycle().take(500).collect();

    // Collect words
    let mut word_counts: HashMap<String, i32> = HashMap::new();
    for text in &training_texts {
        for word in text.split_whitespace() {
            *word_counts.entry(word.to_string()).or_default() += 1;
        }
    }

    let mut words: Vec<Word> = word_counts
        .keys()
        .map(|s| Word {
            ids: s.bytes().map(|b| b as u32).collect(),
        })
        .collect();

    let counts: Vec<i32> = word_counts.values().copied().collect();

    let vocab_size = 300; // Quick benchmark
    let num_merges = vocab_size - 256;
    let mut merges = Vec::new();

    let train_start = Instant::now();

    for _ in 0..num_merges {
        let pair_counts = count_pairs_parallel(&words, &counts);

        let best_pair = pair_counts
            .iter()
            .max_by_key(|(_, &count)| count)
            .map(|(&pair, _)| pair);

        if let Some(pair) = best_pair {
            let new_id = 256 + merges.len() as u32;
            merges.push(pair);

            for word in &mut words {
                word.merge_pair(pair, new_id);
            }
        } else {
            break;
        }
    }

    let train_elapsed = train_start.elapsed();

    println!("  Training time: {}ms", train_elapsed.as_millis());
    println!("  Learned merges: {}", merges.len());
    println!();

    // Benchmark: Encoding (quick: 1000 iterations)
    println!("Benchmark: Encoding Speed");
    println!("{}", "-".repeat(40));

    let test_text = concat!(
        "The quick brown fox jumps over the lazy dog. ",
        "This sentence contains every letter of the alphabet at least once. ",
        "Machine learning models process text by converting it to tokens. ",
        "Byte pair encoding learns frequent subword units from training data. ",
        "Modern language models use BPE tokenization for efficiency."
    );

    let iterations = 1000; // Fixed for hyperfine

    let encode_start = Instant::now();

    for _ in 0..iterations {
        let mut tokens: Vec<u32> = test_text.bytes().map(|b| b as u32).collect();

        // Apply merges
        for &pair in &merges {
            let new_id = 256 + merges.iter().position(|&p| p == pair).unwrap() as u32;
            let mut i = 0;
            let mut new_tokens = Vec::new();
            while i < tokens.len() {
                if i + 1 < tokens.len() && tokens[i] == pair.0 && tokens[i + 1] == pair.1 {
                    new_tokens.push(new_id);
                    i += 2;
                } else {
                    new_tokens.push(tokens[i]);
                    i += 1;
                }
            }
            tokens = new_tokens;
        }
    }

    let encode_elapsed = encode_start.elapsed();
    let per_iter_us = encode_elapsed.as_micros() / iterations as u128;

    println!("  Total time ({} iterations): {}ms", iterations, encode_elapsed.as_millis());
    println!("  Per iteration: {}μs", per_iter_us);
    println!("  Text length: {} bytes", test_text.len());
    println!("  Throughput: {:.2} MB/s",
        (test_text.len() * iterations) as f64 / encode_elapsed.as_secs_f64() / 1_000_000.0
    );
    println!();

    println!("📊 Rust Baseline Established");
    println!("{}", "=".repeat(60));
    println!();
    println!("Compare with: zig build run");
    println!();
}
