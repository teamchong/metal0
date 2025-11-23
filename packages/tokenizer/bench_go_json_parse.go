package main

import (
	"encoding/json"
	"os"
)

func main() {
	data, err := os.ReadFile("sample.json")
	if err != nil {
		panic(err)
	}

	for i := 0; i < 100000; i++ {
		var result interface{}
		if err := json.Unmarshal(data, &result); err != nil {
			panic(err)
		}
	}
}
