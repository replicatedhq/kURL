package cli

import (
	"github.com/pkg/errors"
)

// ErrWarn is the standard 'host preflights have warnings' error
var ErrWarn = errors.New("host preflights have warnings")
