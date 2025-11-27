package main
import ("encoding/json"; "os")
func main() {
    data, _ := os.ReadFile("sample.json")
    for i := 0; i < 50000; i++ { var p interface{}; json.Unmarshal(data, &p) }
}
