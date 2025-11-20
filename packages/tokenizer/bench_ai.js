import { Tokenizer } from 'ai-tokenizer';
import * as o200k from 'ai-tokenizer/encoding/o200k_base';

try {
    const tokenizer = new Tokenizer({
        name: o200k.name,
        patternRegex: new RegExp(o200k.pat_str, 'gu'),
        specialTokensRegex: null,
        specialTokens: o200k.special_tokens,
        stringRankEncoder: o200k.stringEncoder,
        binaryRankEncoder: o200k.binaryEncoder,
        decoder: o200k.decoder
    });

    window.benchAITokenizer = function(text, iterations) {
        // Warmup
        for (let i = 0; i < 100; i++) tokenizer.encode(text);

        // Benchmark
        const start = performance.now();
        for (let i = 0; i < iterations; i++) {
            tokenizer.encode(text);
        }
        return performance.now() - start;
    };

    window.testAITokenizer = function(text) {
        return tokenizer.encode(text).length;
    };
} catch (e) {
    console.error('ai-tokenizer init failed:', e.message);
    window.aiTokenizerError = e.message;
}
