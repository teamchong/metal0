from tokenizers import Tokenizer, trainers, models, pre_tokenizers, normalizers
import json
import time

# Load Shakespeare data
with open('shakespeare_train.jsonl', 'r') as f:
    texts = [json.loads(line)['text'] for line in f]

print(f"Loaded {len(texts)} texts ({sum(len(t) for t in texts):,} chars)")

# Create tokenizer
tokenizer = Tokenizer(models.Unigram())
tokenizer.normalizer = normalizers.NFKC()
tokenizer.pre_tokenizer = pre_tokenizers.Metaspace()

# Create trainer
trainer = trainers.UnigramTrainer(
    vocab_size=32000,
    show_progress=True,
    unk_token="<UNK>",
    max_piece_length=16,
    shrinking_factor=0.75,
    n_sub_iterations=2,
)

# Train and time it
start = time.time()
tokenizer.train_from_iterator(texts, trainer=trainer)
elapsed = time.time() - start

print(f"\nHuggingFace training time: {elapsed*1000:.0f}ms")
print(f"Final vocab size: {tokenizer.get_vocab_size()}")

# Save for comparison
tokenizer.save("hf_shakespeare_trained.json")
