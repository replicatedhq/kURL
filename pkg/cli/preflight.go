package cli

import (
	"fmt"
	"io"
	"strings"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/pkg/installer"
	"github.com/replicatedhq/kurl/pkg/preflight"
	analyze "github.com/replicatedhq/troubleshoot/pkg/analyze"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func NewPreflightCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:          "preflight [installer spec file]",
		Short:        "Runs kURL preflight checks",
		SilenceUsage: true,
		Args:         cobra.ExactArgs(1),
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			return viper.BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			return viper.BindPFlags(cmd.Flags())
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			_, err := installer.RetrieveSpec(cli.GetFS(), args[0])
			if err != nil {
				return errors.Wrap(err, "retrieve installer spec")
			}

			// TODO(ethan): use spec for conditional preflights
			preflightSpec, err := preflight.Decode([]byte(preflight.Builtin()))
			if err != nil {
				return errors.Wrap(err, "decode spec")
			}

			progressChan := make(chan interface{})
			defer close(progressChan)
			go discardProgress(progressChan)

			results, err := cli.GetPreflightRunner().Run(cmd.Context(), preflightSpec, progressChan)
			if err != nil {
				return errors.Wrap(err, "run preflight")
			}

			printPreflightResults(cmd.OutOrStdout(), results)

			switch {
			case preflightIsFail(results):
				return errors.New("preflights have failures")
			case preflightIsWarn(results):
				if viper.GetBool("ignore-warnings") {
					fmt.Fprintln(cmd.ErrOrStderr(), "Warnings ignored by CLI flag \"ignore-warnings\"")
				} else {
					if confirmPreflightIsWarn(cli) {
						return nil
					}
					return errors.New("preflights have warnings")
				}
			}
			return nil
		},
	}

	cmd.Flags().Bool("ignore-warnings", false, "ignore preflight warnings")

	return cmd
}

func discardProgress(ch <-chan interface{}) {
	for range ch {
	}
}

func printPreflightResults(w io.Writer, results []*analyze.AnalyzeResult) {
	for _, result := range results {
		printPreflightResult(w, result)
	}
}

func printPreflightResult(w io.Writer, result *analyze.AnalyzeResult) {
	switch {
	case result.IsPass:
		fmt.Fprintln(w, green("[PASS]"), fmt.Sprintf("%s: %s", result.Title, result.Message))
	case result.IsWarn:
		fmt.Fprintln(w, yellow("[WARN]"), fmt.Sprintf("%s: %s", result.Title, result.Message))
	case result.IsFail:
		fmt.Fprintln(w, red("[FAIL]"), fmt.Sprintf("%s: %s", result.Title, result.Message))
	}
}

func confirmPreflightIsWarn(cli CLI) bool {
	rl := cli.GetReadline()

	rl.SetPrompt("Preflight has warnings. Do you want to proceed anyway? (y/N) ")

	line, err := rl.Readline()
	if err != nil {
		return false
	}

	text := strings.ToLower(strings.TrimSpace(line))
	return text == "y" || text == "yes"
}

func preflightIsFail(results []*analyze.AnalyzeResult) bool {
	for _, result := range results {
		switch {
		case result.IsFail:
			return true
		}
	}
	return false
}

func preflightIsWarn(results []*analyze.AnalyzeResult) bool {
	hasWarn := false
	for _, result := range results {
		switch {
		case result.IsFail:
			return false
		case result.IsWarn:
			hasWarn = true
		}
	}
	return hasWarn
}

func preflightIsPass(results []*analyze.AnalyzeResult) bool {
	for _, result := range results {
		switch {
		case result.IsFail, result.IsWarn:
			return false
		}
	}
	return true
}
