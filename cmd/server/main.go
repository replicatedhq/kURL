package main

import (
	"archive/tar"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path"
	"strings"
	"time"
)

const upstream = "http://localhost:3000"

func main() {
	log.Printf("Commit %s\n", os.Getenv("COMMIT"))

	http.Handle("/bundle/", http.HandlerFunc(bundle))

	upstreamURL, err := url.Parse(upstream)
	if err != nil {
		log.Panic(err)
	}
	proxy := httputil.NewSingleHostReverseProxy(upstreamURL)
	http.Handle("/", proxy)

	log.Println("Listening on :3001")
	err = http.ListenAndServe(":3001", nil)
	if err != nil {
		log.Fatal(err)
	}
}

type BundleManifest struct {
	Layers []string          `json:"layers"`
	Files  map[string]string `json:"files"`
}

func bundle(w http.ResponseWriter, r *http.Request) {
	if r.Method == "OPTIONS" {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET")
		w.Header().Set("Access-Control-Allow-Headers", "Access-Control-Allow-Origin, Content-Type")
		w.Header().Set("Access-Control-Max-Age", "86400")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != "GET" && r.Method != "HEAD" {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}
	log.Printf("GET %s", r.URL.Path)

	base := path.Base(r.URL.Path)
	installerID := strings.TrimSuffix(base, ".tar.gz")
	installerURL := fmt.Sprintf("%s/bundle/%s", upstream, installerID)
	request, err := http.NewRequest("GET", installerURL, nil)
	if err != nil {
		log.Printf("Error building request for %s: %v", installerURL, err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	// forward request headers for metrics
	request.Header = r.Header
	if request.Header.Get("X-Forwarded-For") == "" {
		if host, _, _ := net.SplitHostPort(r.RemoteAddr); host != "" {
			request.Header.Set("X-Forwarded-For", host)
		}
	}
	resp, err := http.DefaultClient.Do(request)
	if err != nil {
		log.Printf("Error fetching %s: %v", installerURL, err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		log.Printf("Error reading response body from %s: %v", installerURL, err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	if resp.StatusCode == http.StatusNotFound {
		http.Error(w, string(body), http.StatusNotFound)
		return
	}
	bundle := &BundleManifest{}
	err = json.Unmarshal(body, bundle)
	if err != nil {
		log.Printf("Error unmarshaling installer bundle manifest from %s: %s: %v", installerURL, body, err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "binary/octet-stream")
	w.Header().Set("Content-Encoding", "gzip")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Disposition", "attachment")
	w.Header().Set("Transfer-Encoding", "chunked")

	if r.Method == "HEAD" {
		return
	}

	wz := gzip.NewWriter(w)
	archive := tar.NewWriter(wz)
	defer func() {
		if err := archive.Close(); err != nil {
			log.Printf("Error closing archive for installer %s: %v", installerID, err)
		}

		if err := wz.Close(); err != nil {
			log.Printf("Error closing gzip stream for installer %s: %v", installerID, err)
		}
	}()

	for _, layerURL := range bundle.Layers {
		if err := pipe(archive, layerURL); err != nil {
			log.Printf("Error piping %s to %s bundle: %v", layerURL, installerID, err)
			return
		}
	}

	for filepath, contents := range bundle.Files {
		archive.WriteHeader(&tar.Header{
			Name:    filepath,
			Size:    int64(len(contents)),
			Mode:    0644,
			ModTime: time.Now(),
		})
		_, err := archive.Write([]byte(contents))
		if err != nil {
			log.Printf("Error writing file %q: %v", filepath, err)
			return
		}
	}

}

func pipe(dst *tar.Writer, srcURL string) error {
	resp, err := http.Get(srcURL)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("response code %d", resp.StatusCode)
	}

	zr, err := gzip.NewReader(resp.Body)
	if err != nil {
		return fmt.Errorf("gunzip response %s", resp.Body)
	}
	defer zr.Close()
	src := tar.NewReader(zr)

	for {
		header, err := src.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return fmt.Errorf("next file: %v", err)
		}
		dst.WriteHeader(header)
		_, err = io.Copy(dst, src)
		if err != nil {
			return fmt.Errorf("copy file contents: %v", err)
		}
	}
}
