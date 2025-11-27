use std::fs;
fn main() {
    let data = fs::read_to_string("sample.json").unwrap();
    for _ in 0..50_000 { let _: serde_json::Value = serde_json::from_str(&data).unwrap(); }
}
