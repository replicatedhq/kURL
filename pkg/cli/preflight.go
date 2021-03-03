package cli

import (
	"context"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/briandowns/spinner"
	"github.com/mattn/go-isatty"
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
			installerSpec, err := installer.RetrieveSpec(cli.GetFS(), args[0])
			if err != nil {
				return errors.Wrap(err, "retrieve installer spec")
			}

			builtin := preflight.Builtin()
			data := installer.TemplateData{
				Installer: *installerSpec,
				IsPrimary: viper.GetBool("is-primary"),
				IsJoin:    viper.GetBool("is-join"),
				IsUpgrade: viper.GetBool("is-upgrade"),
			}
			spec, err := installer.ExecuteTemplate("installerSpec", builtin, data)
			if err != nil {
				return errors.Wrap(err, "execute installer template")
			}

			preflightSpec, err := preflight.Decode(spec)
			if err != nil {
				return errors.Wrap(err, "decode spec")
			}

			progressChan := make(chan interface{})
			progressContext, progressCancel := context.WithCancel(cmd.Context())
			isTerminal := isatty.IsTerminal(os.Stderr.Fd())
			go writeProgress(cmd.ErrOrStderr(), progressChan, progressCancel, isTerminal)

			results, err := cli.GetPreflightRunner().Run(cmd.Context(), preflightSpec, progressChan)
			close(progressChan)
			<-progressContext.Done()

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
	cmd.Flags().Bool("is-primary", true, "set to true if this node is a primary")
	cmd.Flags().Bool("is-join", false, "set to true if this node is joining an existing cluster (non-primary implies join)")
	cmd.Flags().Bool("is-upgrade", false, "set to true if this is an upgrade")

	return cmd
}

var collectorStartRegexp = regexp.MustCompile(`^\[.+\] Running collector\.\.\.$`)

func writeProgress(w io.Writer, ch <-chan interface{}, cancel func(), isTerminal bool) {
	var sp *spinner.Spinner
	for line := range ch {
		s := fmt.Sprintf("%s", line)
		if collectorStartRegexp.MatchString(s) {
			if sp != nil {
				sp.Stop()
			}
			fmt.Fprintln(w, s)
			if isTerminal {
				sp = spinner.New(
					spinner.CharSets[9],
					100*time.Millisecond,
					spinner.WithWriter(w),
					spinner.WithColor("reset"),
					spinner.WithFinalMSG("✔ complete\n"),
				)
				sp.Start()
			}
		} else {
			if sp != nil {
				sp.Suffix = fmt.Sprintf(" %s", line)
			}
		}
	}
	if sp != nil {
		sp.Stop()
	}
	cancel()
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

	rl.SetPrompt("Preflight has warnings. Do you want to proceed anyway? (Y/n) ")

	line, err := rl.Readline()
	if err != nil {
		return true
	}

	text := strings.ToLower(strings.TrimSpace(line))
	return !(text == "n" || text == "no")
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
