package rook

import (
	"context"
	"fmt"
	"io"
	"time"
)

var outputWriter io.Writer
var rewriteType = rewriteNone

const (
	rewriteNone = iota
	rewriteSpinner
	rewriteLine
	rewriteNewline
)

func InitWriter(wr io.Writer) {
	outputWriter = wr
}

// writes a new line with the provided output
func out(out string) {
	if rewriteType != rewriteNone {
		fmt.Fprintf(outputWriter, "\n")
	}
	rewriteType = rewriteNone
	if outputWriter != nil {
		fmt.Fprintf(outputWriter, "%s\n", out)
	}
}

// when first called, writes a new line with the provided string.
// on second+ consecutive calls in a row, deletes the previous line and writes a new one.
// this allows printing a dynamic progress message without filling the screen, for instance "recovery 10.05% complete"
func spinLine(newLine string) {
	if outputWriter == nil || newLine == "" {
		return
	}

	if rewriteType == rewriteLine {
		fmt.Fprintf(outputWriter, "\033[2K\r%s", newLine)
	} else {
		rewriteType = rewriteLine
		fmt.Fprintf(outputWriter, "%s", newLine)
	}
}

var previousUpdatedLine string

// when first called, writes a new line with the provided string.
// on second+ consecutive calls in a row, writes a new line if the content has changed.
// useful for "waiting for X, Y and Z to complete" style messages.
func updatedLine(newLine string) {
	if outputWriter == nil || newLine == "" {
		return
	}

	if rewriteType != rewriteNewline || newLine != previousUpdatedLine {
		rewriteType = rewriteNewline
		previousUpdatedLine = newLine
		fmt.Fprintf(outputWriter, "%s\n", newLine)
	}
}

const spinnerchars = "|/-\\"

var spinnerPos = 0

// prints a spinner - [|], [/], [-], [\]
func spinner() {
	if outputWriter == nil {
		return
	}

	if rewriteType == rewriteSpinner { // delete the three character spinner
		fmt.Fprintf(outputWriter, "\033[2K\r")
	} else {
		rewriteType = rewriteSpinner
		spinnerPos = 0
	}
	fmt.Fprintf(outputWriter, "[%c]", spinnerchars[spinnerPos%len(spinnerchars)])
	spinnerPos++
}

// prints a spinner until the duration has elapsed or the context is cancelled
func spinWait(ctx context.Context, duration time.Duration) {
	timeoutCtx, cancel := context.WithTimeout(ctx, duration)
	defer cancel()
	for {
		select {
		case <-time.After(time.Second):
			spinner()
		case <-timeoutCtx.Done():
			return
		}
	}
}
