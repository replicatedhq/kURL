package util

import (
	"io"

	"github.com/pborman/ansi"
)

type StripANSIWriter struct {
	w io.Writer
}

func NewStripANSIWriter(w io.Writer) *StripANSIWriter {
	return &StripANSIWriter{w: w}
}

func (w *StripANSIWriter) Write(in []byte) (int, error) {
	out, err := ansi.Strip(in)
	if err != nil {
		return 0, err
	}
	return w.w.Write(out)
}
