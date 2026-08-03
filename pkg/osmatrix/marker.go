package osmatrix

import (
	"fmt"
	"strings"
)

// Marker sentinels. A generated region in a hand-maintained file is delimited by
// a BEGIN line and an END line, each carrying the region id. The generator
// replaces the lines strictly between them; everything else in the file
// (including the marker lines themselves and their indentation) is left byte-for
// -byte untouched. Markers are introduced once, by hand, where an OS-derived
// region lives; thereafter `make generate-os-matrix` keeps the region in sync
// with os-matrix.yaml.
const (
	markerBeginSentinel = "BEGIN GENERATED os-matrix:"
	markerEndSentinel   = "END GENERATED os-matrix:"
)

// SpliceRegion replaces the lines between the BEGIN and END markers for the
// given region id with body, preserving the marker lines and all other bytes.
// The trailing newline (if any) of the input is preserved.
func SpliceRegion(content []byte, id string, body []string) ([]byte, error) {
	hadTrailingNewline := strings.HasSuffix(string(content), "\n")
	text := strings.TrimSuffix(string(content), "\n")
	lines := strings.Split(text, "\n")

	beginTok := markerBeginSentinel + " " + id
	endTok := markerEndSentinel + " " + id

	begin, end := -1, -1
	for i, l := range lines {
		if strings.Contains(l, beginTok) {
			if begin != -1 {
				return nil, fmt.Errorf("duplicate BEGIN marker for region %q", id)
			}
			begin = i
		}
		if strings.Contains(l, endTok) {
			if end != -1 {
				return nil, fmt.Errorf("duplicate END marker for region %q", id)
			}
			end = i
		}
	}
	if begin == -1 || end == -1 {
		return nil, fmt.Errorf("region %q markers not found (begin=%d end=%d)", id, begin, end)
	}
	if end <= begin {
		return nil, fmt.Errorf("region %q END marker precedes BEGIN", id)
	}

	out := make([]string, 0, len(lines)-(end-begin-1)+len(body))
	out = append(out, lines[:begin+1]...)
	out = append(out, body...)
	out = append(out, lines[end:]...)

	result := strings.Join(out, "\n")
	if hadTrailingNewline {
		result += "\n"
	}
	return []byte(result), nil
}
