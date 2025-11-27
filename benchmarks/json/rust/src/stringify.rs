use std::fs;
fn main() {
    let data = fs::read_to_string("sample.json").unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&data).unwrap();
    for _ in 0..50_000 { let _ = serde_json::to_string(&parsed).unwrap(); }
}
