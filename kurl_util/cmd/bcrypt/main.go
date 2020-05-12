package main

import (
	"bufio"
	"flag"
	"fmt"
	"log"
	"os"

	"golang.org/x/crypto/bcrypt"
)

func main() {
	cost := flag.Int("cost", 14, "cost")
	flag.Parse()

	scanner := bufio.NewScanner(os.Stdin)

	for scanner.Scan() {
		password := scanner.Bytes()
		hash, err := bcrypt.GenerateFromPassword(password, *cost)
		if err != nil {
			log.Fatal(err)
		}
		fmt.Println(string(hash))
	}
}
