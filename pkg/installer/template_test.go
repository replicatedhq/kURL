package installer

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_zero(t *testing.T) {
	type C struct {
		D *string
	}
	type B struct {
		C *C
	}
	type A struct {
		B *B
	}
	scp := "scalar_ptr"

	input := struct {
		Scalar    string
		ScalarPtr *string
		A         A
		AP        *A
		APN       *A
	}{
		Scalar:    "scalar",
		ScalarPtr: &scp,
		A:         A{B: &B{C: &C{D: &scp}}},
		AP:        &A{},
		APN:       nil,
	}
	want := struct {
		Scalar    string
		ScalarPtr *string
		A         A
		AP        *A
		APN       *A
	}{
		Scalar:    "scalar",
		ScalarPtr: &scp,
		A:         A{B: &B{C: &C{D: &scp}}},
		AP:        &A{B: &B{C: &C{D: new(string)}}},
		APN:       &A{B: &B{C: &C{D: new(string)}}},
	}

	zero(&input)
	assert.EqualValues(t, want, input)
}
