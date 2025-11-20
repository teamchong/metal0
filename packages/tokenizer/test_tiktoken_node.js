import * as tiktoken from './node_modules/tiktoken/tiktoken.js';

const enc = tiktoken.get_encoding('cl100k_base');
const text = "Hello world";
const tokens = enc.encode(text);
console.log('Tokens:', tokens.length);
enc.free();
