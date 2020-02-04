// Copyright (c) 2019 Uber Technologies, Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

package parallel

import "time"

func newEvent(e EventType, t time.Time, f map[string]interface{}, err error) *Event {
	var errString string
	if err != nil {
		errString = err.Error()
	}
	return &Event{e, t, f, errString}
}

func newStartedEvent(t time.Time) *Event {
	return newEvent(EventTypeStarted, t, nil, nil)
}

func newCmdStartedEvent(t time.Time, cmd Cmd) *Event {
	return newEvent(EventTypeCmdStarted, t, map[string]interface{}{
		"cmd": cmd.String(),
	}, nil)
}

func newCmdFinishedEvent(t time.Time, cmd Cmd, startTime time.Time, err error) *Event {
	return newEvent(EventTypeCmdFinished, t, map[string]interface{}{
		"cmd":      cmd.String(),
		"duration": t.Sub(startTime).String(),
	}, err)
}

func newFinishedEvent(t time.Time, startTime time.Time, err error) *Event {
	return newEvent(EventTypeFinished, t, map[string]interface{}{
		"duration": t.Sub(startTime).String(),
	}, err)
}
