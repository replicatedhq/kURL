package main

import (
	"bytes"
	"fmt"
	"github.com/otiai10/copy"
	"github.com/stretchr/testify/require"
	"io/fs"
	"io/ioutil"
	"os"
	"path"
	"strings"
	"testing"
)

func Test_generateIDs(t *testing.T) {
	tt := []struct{
		name string
		dryRun bool
	}{
		{
			name: "happy-path",
		},

	}

	for _, tc := range tt {
		t.Run(tc.name, func(t *testing.T){
			tempDir :=t.TempDir()
			rootDir := path.Join(tempDir, tc.name)
			var output bytes.Buffer
			// copy test files into temp,
			require.Nil(t, copy.Copy(path.Join("testdata", tc.name, "input"), rootDir))
			require.Nil(t, generateIDs(rootDir, &output, tc.dryRun ))
			compareDir := "expected"
			// if dryRun we don't expect the files to change
			if tc.dryRun {
				compareDir = "input"
			}

			compareResults(t,
				path.Join("testdata", tc.name, compareDir),
				rootDir,
				)
		})
	}
}

func compareResults(t *testing.T, expected, actual string) {
	fileMap := map[string][]string  {}
	require.Nil(t, fs.WalkDir(os.DirFS(expected), "." , testWalker(expected, fileMap)))
	require.Nil(t, fs.WalkDir(os.DirFS(actual), ".", testWalker(actual, fileMap)))
	for _, v := range fileMap {
		require.Len(t, v, 4)
		require.Equalf(t, v[1], v[3], "compare %q to %q", v[0], v[1])
	}

}



func testWalker( root string, fm map[string][]string ) func(p string, d fs.DirEntry, err error) error {
	return func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		if strings.HasSuffix(d.Name(), "yaml") {

			fullPath := path.Join(root, p)
			fmt.Printf("processing path %q full path %q\n", p, fullPath)

			contents, err := ioutil.ReadFile(fullPath)
			if err != nil {
				return err
			}
			fm[p] = append(fm[p], fullPath, string(contents))
		}
		return nil
	}
}