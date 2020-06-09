package main

import (
	"flag"
	"log"
	"os"

	"github.com/foomo/htpasswd"
)

func main() {
	username := flag.String("u", "", "username")
	password := flag.String("p", "", "password")
	filePath := flag.String("f", "", "filePath")

	flag.Parse()

	if *username == "" || *password == "" {
		flag.PrintDefaults()
		os.Exit(-1)
	}

	if err := htpasswd.SetPassword(*filePath, *username, *password, htpasswd.HashBCrypt); err != nil {
		log.Fatal(err)
	}
}
