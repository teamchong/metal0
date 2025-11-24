from tokenizers import Tokenizer, trainers, models, pre_tokenizers
import json

# Load data
with open('benchmark_data.json', 'r') as f:
    data = json.load(f)
texts = data['texts'][:100]  # Use subset for quick test

print(f"Training on {len(texts)} texts...")

# Train HF BPE
tokenizer = Tokenizer(models.BPE())
trainer = trainers.BpeTrainer(vocab_size=1000, show_progress=False)
tokenizer.train_from_iterator(texts, trainer=trainer)

print(f"HF BPE vocab size: {tokenizer.get_vocab_size()}")

# Save for comparison
tokenizer.save("hf_bpe_test.json")
print("Saved HF BPE tokenizer")
