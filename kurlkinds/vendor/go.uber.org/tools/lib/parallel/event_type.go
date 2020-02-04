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

import (
	"fmt"
	"strconv"
	"strings"
)

const (
	// EventTypeStarted says that the runner started.
	EventTypeStarted EventType = iota + 1
	// EventTypeCmdStarted says that a command started.
	EventTypeCmdStarted
	// EventTypeCmdFinished says that a command finished.
	EventTypeCmdFinished
	// EventTypeFinished says that the runner finished.
	EventTypeFinished
)

var allEventTypes = []EventType{
	EventTypeStarted,
	EventTypeCmdStarted,
	EventTypeCmdFinished,
	EventTypeFinished,
}

// EventType is an event type during the runner's run call.
type EventType int

// String returns a string representation of the EventType.
func (e EventType) String() string {
	switch e {
	case EventTypeStarted:
		return "started"
	case EventTypeCmdStarted:
		return "cmd_started"
	case EventTypeCmdFinished:
		return "cmd_finished"
	case EventTypeFinished:
		return "finished"
	default:
		return strconv.Itoa(int(e))
	}
}

// MarshalJSON marshals the EventType to JSON.
func (e EventType) MarshalJSON() ([]byte, error) {
	return []byte(`"` + e.String() + `"`), nil
}

// UnmarshalJSON unmarshals the EventType from JSON.
func (e *EventType) UnmarshalJSON(data []byte) error {
	dataString := strings.ToLower(string(data))
	switch dataString {
	case `"started"`:
		*e = EventTypeStarted
	case `"cmd_started"`:
		*e = EventTypeCmdStarted
	case `"cmd_finished"`:
		*e = EventTypeCmdFinished
	case `"finished"`:
		*e = EventTypeFinished
	default:
		return invalidEventType(data, "json")
	}
	return nil
}

// MarshalText marshals the EventType to text.
func (e EventType) MarshalText() ([]byte, error) {
	return []byte(e.String()), nil
}

// UnmarshalText unmarshals the EventType from text.
func (e *EventType) UnmarshalText(data []byte) error {
	dataString := strings.ToLower(string(data))
	switch dataString {
	case "started":
		*e = EventTypeStarted
	case "cmd_started":
		*e = EventTypeCmdStarted
	case "cmd_finished":
		*e = EventTypeCmdFinished
	case "finished":
		*e = EventTypeFinished
	default:
		return invalidEventType(data, "text")
	}
	return nil
}

func invalidEventType(data []byte, format string) error {
	return fmt.Errorf("invalid EventType for %s: %s", format, string(data))
}
