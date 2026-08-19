package osmatrix

import (
	"strings"
	"testing"
)

func TestSpliceRegion(t *testing.T) {
	file := strings.Join([]string{
		"before line",
		"# BEGIN GENERATED os-matrix: demo",
		"old generated 1",
		"old generated 2",
		"# END GENERATED os-matrix: demo",
		"after line",
	}, "\n") + "\n"

	got, err := SpliceRegion([]byte(file), "demo", []string{"new gen A", "new gen B", "new gen C"})
	if err != nil {
		t.Fatalf("SpliceRegion: %v", err)
	}
	want := strings.Join([]string{
		"before line",
		"# BEGIN GENERATED os-matrix: demo",
		"new gen A",
		"new gen B",
		"new gen C",
		"# END GENERATED os-matrix: demo",
		"after line",
	}, "\n") + "\n"
	if string(got) != want {
		t.Errorf("splice mismatch:\n got %q\nwant %q", got, want)
	}
}

func TestSpliceRegionPreservesMarkerIndentAndOutsideBytes(t *testing.T) {
	file := "x\n        # BEGIN GENERATED os-matrix: c\n        junk\n        # END GENERATED os-matrix: c\n            ;;\n"
	got, err := SpliceRegion([]byte(file), "c", []string{"        ubuntu18.04|ubuntu26.04)"})
	if err != nil {
		t.Fatalf("SpliceRegion: %v", err)
	}
	want := "x\n        # BEGIN GENERATED os-matrix: c\n        ubuntu18.04|ubuntu26.04)\n        # END GENERATED os-matrix: c\n            ;;\n"
	if string(got) != want {
		t.Errorf("indent/outside mismatch:\n got %q\nwant %q", got, want)
	}
}

func TestSpliceRegionEmptyBody(t *testing.T) {
	file := "a\n# BEGIN GENERATED os-matrix: z\ngone\n# END GENERATED os-matrix: z\nb\n"
	got, err := SpliceRegion([]byte(file), "z", nil)
	if err != nil {
		t.Fatalf("SpliceRegion: %v", err)
	}
	want := "a\n# BEGIN GENERATED os-matrix: z\n# END GENERATED os-matrix: z\nb\n"
	if string(got) != want {
		t.Errorf("empty-body mismatch:\n got %q\nwant %q", got, want)
	}
}

func TestSpliceRegionErrors(t *testing.T) {
	// Missing markers.
	if _, err := SpliceRegion([]byte("no markers here\n"), "x", []string{"y"}); err == nil {
		t.Error("expected error when markers absent")
	}
	// END before BEGIN.
	bad := "# END GENERATED os-matrix: x\n# BEGIN GENERATED os-matrix: x\n"
	if _, err := SpliceRegion([]byte(bad), "x", []string{"y"}); err == nil {
		t.Error("expected error when END precedes BEGIN")
	}
	// Duplicate BEGIN.
	dup := "# BEGIN GENERATED os-matrix: x\n# BEGIN GENERATED os-matrix: x\n# END GENERATED os-matrix: x\n"
	if _, err := SpliceRegion([]byte(dup), "x", []string{"y"}); err == nil {
		t.Error("expected error on duplicate BEGIN marker")
	}
}
