// metal0 WASM Runtime - Generic Immer-style loader
// Works with ANY metal0-compiled WASM module
const E=new TextEncoder();let w,m,p,M=1<<20;
const g=()=>new Uint8Array(m.buffer,p,M);
const x=a=>{
  if(typeof a!=='string')return[a];
  const b=E.encode(a);
  if(b.length>M){M=b.length+1024;p=w.alloc(M)}
  g().set(b);return[p,b.length];
};
export async function load(s){
  const b=typeof s==='string'?await fetch(s).then(r=>r.arrayBuffer()):s;
  w=(await WebAssembly.instantiate(await WebAssembly.compile(b),{})).exports;
  m=w.memory;  // use WASM's exported memory
  if(w.alloc){p=w.alloc(M)}
  return new Proxy({},{get:(_,n)=>n==='batch'?batch:typeof w[n]==='function'?(...a)=>w[n](...a.flatMap(x)):w[n]});
}
export const batch=(i,f)=>i.map(a=>w[f](...[a].flatMap(x)));
