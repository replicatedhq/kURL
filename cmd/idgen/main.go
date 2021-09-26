package main

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"io/ioutil"
	"log"
	"os"
	"path"
	"reflect"
	"regexp"
	"strings"

	"github.com/replicatedhq/kurl/pkg/preflight"
	"github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
	serializer "k8s.io/apimachinery/pkg/runtime/serializer/json"
)

func main() {
	var dryRun bool
	var rootPath string
	defaultRootPath, err := os.Getwd()
	if err != nil {
		log.Fatalf("could not retrieve working dir %s", err)
	}
	flag.StringVar(&rootPath, "r", defaultRootPath, "path where files containing HostPreflights is rooted")
	flag.BoolVar(&dryRun, "d", false, "if set, program will output results but no files will be changed")
	flag.Parse()
	if err := generateIDs(rootPath, os.Stdout, dryRun); err != nil {
		log.Fatalf("id generation failed with %q", err)
	}
}

func generateIDs(rootPath string, out io.Writer, dryRun bool) error {
	idMapper := map[string]struct{}{}
	return fs.WalkDir(os.DirFS(rootPath), ".", getFilesystemWalker(rootPath, idMapper, out, dryRun))
}

func getFilesystemWalker(root string, idMap map[string]struct{}, _ io.Writer, _ bool) func(string, fs.DirEntry, error) error {

	return func(relPath string, de fs.DirEntry, fsErr error) error {
		if fsErr != nil {
			log.Printf("file system error %q skipping %q", fsErr, relPath)
			return nil
		}
		if de.IsDir() {
			return nil
		}
		if strings.HasSuffix(de.Name(), ".yaml") {
			fullPath := path.Join(root, relPath)
			contents, err := ioutil.ReadFile(fullPath)
			if err != nil {
				return err
			}

			sanitizer := regexp.MustCompile(`\n\s*\{\{kurl`)
			commented := sanitizer.ReplaceAll(contents, []byte("#{{kurl"))

			crd, _ := preflight.Decode(commented)
			if crd == nil {
				return nil
			}

			crdWithIDs := addMissingIDs(crd, idMap)

			var wrt bytes.Buffer

			ss := serializer.NewSerializerWithOptions(nil, nil, nil, serializer.SerializerOptions{
				Yaml: true,
			})
			if err := ss.Encode(crdWithIDs, &wrt); err != nil {
				return err
			}

			// now we have to replace the template expressions we commented out
			//withTemplatesAndComments := replaceTemplatesAndComments(contents, wrt.Bytes())

			if err := ioutil.WriteFile(fullPath, wrt.Bytes(), 0644); err != nil {
				return err
			}

		}
		return nil
	}
}

func addMissingIDs(hp *v1beta2.HostPreflight, idMap map[string]struct{}) *v1beta2.HostPreflight {
	for _, analyzer := range hp.Spec.Analyzers {
		analyzerValue := reflect.ValueOf(*analyzer)
		for i := 0; i < analyzerValue.NumField(); i++ {

			f := analyzerValue.Field(i)

			if !f.IsNil() {

				check := reflect.Indirect(f)
				if id, ok := check.Type().FieldByName("ID"); ok {
					if checkName, ok := check.Type().FieldByName("CheckName"); ok {
						idVal := check.FieldByIndex(id.Index).String()
						checkNameVal := check.FieldByIndex(checkName.Index).String()
						newIdVal := generateID(idVal, checkNameVal, idMap)
						check.FieldByIndex(id.Index).SetString(newIdVal)
					}
				}

			}
		}

	}
	return hp
}

var replaceExpr = regexp.MustCompile(`\W`)

func generateID(id, check string, idMap map[string]struct{}) string {
	// id already generated just use it and move on
	if id != "" {
		// regenerate id if someone else is using it so we are always getting unique values
		if _, ok := idMap[id]; ok {
			return generateID("", check, idMap)
		}
		return id
	}
	// generate id from check name replacing all non-alphanumeric characters
	// with underscores and make result lower case
	newId := strings.ToLower(replaceExpr.ReplaceAllString(check, "_"))
	// if new id is already in use append the number of tries to the id to attempt to
	// make a new unique id, and try again until we get one that is unique
	testId := newId
	for i := 0; ; i++ {
		if _, ok := idMap[testId]; !ok {
			idMap[testId] = struct{}{}
			return testId
		}
		testId = fmt.Sprintf("%s_%d", newId, i)
	}
}
