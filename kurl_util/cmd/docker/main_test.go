package main

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_mergeConfigData(t *testing.T) {
	tests := []struct {
		name      string
		oldConfig []byte
		newConfig []byte
		want      []byte
		wantError bool
	}{
		{
			name:      "both configs are empty",
			oldConfig: nil,
			newConfig: nil,
			want:      nil,
			wantError: false,
		},
		{
			name:      "old config is empty",
			oldConfig: nil,
			newConfig: []byte(`{"key": "newVal"}`),
			want:      []byte(`{"key": "newVal"}`),
			wantError: false,
		},
		{
			name:      "new config is empty",
			oldConfig: []byte(`{"key": "oldVal"}`),
			newConfig: nil,
			want:      []byte(`{"key": "oldVal"}`),
			wantError: false,
		},
		{
			name: "both config are non-empty",
			oldConfig: []byte(`{
  "oldKey": "oldVal",
  "commonKey1": {"subKey1": "oldVal1", "subKey2": "oldVal2"}
}`),
			newConfig: []byte(`{
  "oldKey": "newVal",
  "commonKey1": {"subKey2": "newVal2"}
}`),
			want: []byte(`{
  "oldKey": "newVal",
  "commonKey1": {"subKey1": "oldVal1", "subKey2": "newVal2"}
}`),
			wantError: false,
		},

		{
			name:      "old config is empty json",
			oldConfig: []byte(`{}`),
			newConfig: []byte(`{
  "newKey": "oldVal",
  "commonKey1": {"subKey2": "newVal2"}
}`),
			want: []byte(`{
  "newKey": "oldVal",
  "commonKey1": {"subKey2": "newVal2"}
}`),
			wantError: false,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			req := require.New(t)

			mergedConfig, err := mergeConfigData(test.oldConfig, test.newConfig)
			if test.wantError {
				req.Error(err)
			} else {
				req.NoError(err)
			}

			var mergedMap, wantMap interface{}
			_ = json.Unmarshal(mergedConfig, &mergedMap)
			_ = json.Unmarshal(test.want, &wantMap)
			assert.Equal(t, wantMap, mergedMap)
		})
	}
}
