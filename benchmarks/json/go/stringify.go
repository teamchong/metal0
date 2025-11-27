package main
import ("encoding/json"; "os")
func main() {
    data, _ := os.ReadFile("sample.json")
    var p interface{}; json.Unmarshal(data, &p)
    for i := 0; i < 50000; i++ { json.Marshal(p) }
}
