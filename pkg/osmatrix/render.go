package osmatrix

import (
	"fmt"
	"strings"
)

// RenderPool renders a testgrid OS-definition file (testgrid/specs/<name>.yaml)
// from the named pool. Output is byte-for-byte what the committed spec contains,
// including per-pool trailing-newline behavior.
func (m *Matrix) RenderPool(name string) ([]byte, error) {
	p, ok := m.Pool(name)
	if !ok {
		return nil, fmt.Errorf("unknown pool %q", name)
	}

	var lines []string
	for _, id := range p.IDs {
		o, ok := m.OS(id)
		if !ok {
			return nil, fmt.Errorf("pool %q references unknown os id %q", name, id)
		}
		lines = append(lines, o.renderBlockLines()...)
	}

	out := strings.Join(lines, "\n")
	if p.TrailingNewline {
		out += "\n"
	}
	return []byte(out), nil
}

// renderBlockLines renders one OS definition as the list of YAML lines it
// occupies in a testgrid OS-spec file (no trailing newline handling; the caller
// joins lines with "\n").
func (o *OS) renderBlockLines() []string {
	lines := []string{
		fmt.Sprintf("- id: %s", o.ID),
		fmt.Sprintf("  name: %s", o.Name),
		fmt.Sprintf("  version: %q", o.Version),
		fmt.Sprintf("  vmimageuri: %s", o.VMImageURI),
	}
	lines = append(lines, o.renderPreinitLines()...)
	return lines
}

// renderPreinitLines renders the `preinit:` key according to the OS's style.
func (o *OS) renderPreinitLines() []string {
	switch o.PreinitStyle {
	case PreinitBlock:
		out := []string{"  preinit: |"}
		script := strings.TrimRight(o.Preinit, "\n")
		for _, l := range strings.Split(script, "\n") {
			if l == "" {
				out = append(out, "")
				continue
			}
			out = append(out, "    "+l)
		}
		return out
	case PreinitQuoted:
		return []string{fmt.Sprintf("  preinit: %q", o.Preinit)}
	case PreinitEmpty:
		return []string{`  preinit: ""`}
	default:
		return []string{`  preinit: ""`}
	}
}
