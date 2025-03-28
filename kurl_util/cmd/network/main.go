package main

import (
	"context"
	"flag"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

func main() {
	var isServer bool
	var isClient bool
	var address string
	var request string
	var response string

	flag.BoolVar(&isServer, "server", false, "Run the server component")
	flag.BoolVar(&isClient, "client", false, "Run the client component")
	flag.StringVar(&address, "address", "", "IP to attempt to connect to the server")
	flag.StringVar(&request, "request", "kurl-client", "Request body sent by client")
	flag.StringVar(&response, "response", "kurl-server", "Response body sent by server")

	flag.Parse()

	exit := make(chan bool)

	if isServer {
		server := &http.Server{
			Addr: ":8080",
		}
		http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
			body, err := io.ReadAll(r.Body)
			if err != nil {
				log.Println(err.Error())
				return
			}
			if string(body) != request {
				log.Printf("Got request %q, want %q", string(body), request)
				http.Error(w, "Bad Request", http.StatusBadRequest)
				return
			}
			_, err = w.Write([]byte(response))
			if err != nil {
				log.Println(err.Error())
				return
			}
			go func() {
				_ = server.Shutdown(context.Background())
				exit <- true
			}()
		})

		log.Printf("Listening on %s", server.Addr)
		err := server.ListenAndServe()
		if err != http.ErrServerClosed {
			log.Println(err.Error())
			os.Exit(1)
		}

		<-exit
		log.Println("Success")
		return
	}

	if isClient {
		for {
			time.Sleep(time.Second)

			resp, err := http.Post(address, "text/plain", strings.NewReader(request))
			if err != nil {
				log.Println(err.Error())
				continue
			}
			defer resp.Body.Close()
			body, err := io.ReadAll(resp.Body)
			if err != nil {
				log.Println(err.Error())
				continue
			}
			if string(body) != response {
				log.Printf("Got response %q, want %q", string(body), response)
				continue
			}
			log.Println("Success")
			break
		}
		return
	}

	log.Println("Either --server or --client is required")
	os.Exit(1)
}
