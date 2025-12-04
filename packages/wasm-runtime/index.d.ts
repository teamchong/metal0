/** Load any metal0 WASM module */
export declare function load<T extends object>(wasmSource: string | BufferSource): Promise<T & { batch: typeof batch }>;
/** Batch process multiple inputs */
export declare function batch<R>(inputs: any[], funcName: string): R[];
