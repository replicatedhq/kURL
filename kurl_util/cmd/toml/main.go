package main

import (
	"flag"
	"io/ioutil"
	"log"

	"github.com/pelletier/go-toml"
)

func main() {
	var basefile string
	var patchfile string

	flag.StringVar(&basefile, "basefile", "/etc/containerd/config.toml", "filename the patch will be applied to")
	flag.StringVar(&patchfile, "patchfile", "/tmp/containerd.toml", "filename of the patch")

	flag.Parse()

	base, err := toml.LoadFile(basefile)
	if err != nil {
		log.Fatalf("Failed to load %s: %v", basefile, err)
	}
	patch, err := toml.LoadFile(patchfile)
	if err != nil {
		log.Fatalf("Failed to load %s: %v", patchfile, err)
	}

	str := merge(base, patch)
	if err := ioutil.WriteFile(basefile, []byte(str), 0644); err != nil {
		log.Fatalf("Failed to write %s", basefile)
	}
}

func merge(base, patch *toml.Tree) string {
	patchKeys := listLeaves(patch)
	for _, patchKey := range patchKeys {
		patchVal := patch.GetPath(patchKey)
		base.SetPath(patchKey, patchVal)
	}

	return base.String()
}

func listLeaves(tree *toml.Tree, path ...string) [][]string {
	var leaves [][]string

	keys := tree.Keys()
	for _, key := range keys {
		v := tree.GetPath([]string{key})

		fullKeyPath := append([]string{}, path...)
		fullKeyPath = append(fullKeyPath, key)

		switch val := v.(type) {
		case *toml.Tree:
			subTreeLeaves := listLeaves(val, fullKeyPath...)
			leaves = append(leaves, subTreeLeaves...)
		default:
			leaves = append(leaves, fullKeyPath)
		}
	}

	return leaves
}
