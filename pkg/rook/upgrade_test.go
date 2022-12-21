package rook

import (
	"testing"
)

func Test_normalizeRookVersion(t *testing.T) {
	type args struct {
		v string
	}
	tests := []struct {
		name string
		args args
		want string
	}{
		{
			name: "v1.4.6",
			args: args{
				v: "v1.4.6",
			},
			want: "1.4.6",
		},
		{
			name: "1.4.6",
			args: args{
				v: "1.4.6",
			},
			want: "1.4.6",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := normalizeRookVersion(tt.args.v); got != tt.want {
				t.Errorf("normalizeRookVersion() = %v, want %v", got, tt.want)
			}
		})
	}
}
