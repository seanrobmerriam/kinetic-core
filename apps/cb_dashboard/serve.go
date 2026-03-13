//go:build ignore
// +build ignore

package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	fs := http.FileServer(http.Dir("dist"))
	http.Handle("/", fs)

	fmt.Println("IronLedger Dashboard Server starting on http://localhost:8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
