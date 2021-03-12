package cli

import (
	"context"
	"fmt"
	"io"
	"io/ioutil"
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
	troubleshootv1beta2 "github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
	"github.com/replicatedhq/troubleshoot/pkg/collect"
	"github.com/spf13/cobra"
)

func NewHostPreflightCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:          "preflight [installer spec file]",
		Short:        "Runs kURL host preflight checks",
		SilenceUsage: true,
		Args:         cobra.ExactArgs(1),
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			installerSpec, err := installer.RetrieveSpec(cli.GetFS(), args[0])
			if err != nil {
				return errors.Wrap(err, "retrieve installer spec")
			}

			data := installer.TemplateData{
				Installer: *installerSpec,
				IsPrimary: cli.GetViper().GetBool("is-primary"),
				IsJoin:    cli.GetViper().GetBool("is-join"),
				IsUpgrade: cli.GetViper().GetBool("is-upgrade"),
			}

			builtin := preflight.Builtin()
			preflightSpec, err := decodePreflightSpec(builtin, data)
			if err != nil {
				return errors.Wrap(err, "builtin")
			}

			for _, filename := range cli.GetViper().GetStringSlice("spec") {
				spec, err := ioutil.ReadFile(filename)
				if err != nil {
					return errors.Wrapf(err, "read spec file %s", filename)
				}

				decoded, err := decodePreflightSpec(string(spec), data)
				if err != nil {
					return errors.Wrap(err, filename)
				}

				for _, collector := range decoded.Spec.Collectors {
					preflightSpec.Spec.Collectors = maybeAppendPreflightCollector(preflightSpec.Spec.Collectors, collector)
				}
				for _, analyzer := range decoded.Spec.Analyzers {
					preflightSpec.Spec.Analyzers = maybeAppendPreflightAnalyzer(preflightSpec.Spec.Analyzers, analyzer)
				}
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
				if cli.GetViper().GetBool("ignore-warnings") {
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
	cmd.Flags().Bool("is-join", false, "set to true if this node is joining an existing cluster (non-primary implies join)")
	cmd.Flags().Bool("is-primary", true, "set to true if this node is a primary")
	cmd.Flags().Bool("is-upgrade", false, "set to true if this is an upgrade")
	cmd.Flags().StringSlice("spec", nil, "preflight specs")
	// cmd.MarkFlagRequired("spec")
	cmd.MarkFlagFilename("spec", "yaml", "yml")

	return cmd
}

func decodePreflightSpec(raw string, data installer.TemplateData) (*troubleshootv1beta2.HostPreflight, error) {
	spec, err := installer.ExecuteTemplate("installerSpec", raw, data)
	if err != nil {
		return nil, errors.Wrapf(err, "execute installer template")
	}

	decoded, err := preflight.Decode(spec)
	return decoded, errors.Wrap(err, "decode spec")
}

func maybeAppendPreflightCollector(collectors []*troubleshootv1beta2.HostCollect, collector *troubleshootv1beta2.HostCollect) []*troubleshootv1beta2.HostCollect {
	hostCollector, _ := collect.GetHostCollector(collector)
	if hostCollector == nil {
		return collectors
	}
	for _, c := range collectors {
		hc, _ := collect.GetHostCollector(c)
		if hc == nil {
			continue
		} else if hostCollector.Title() == hc.Title() {
			return collectors
		}
	}
	return append(collectors, collector)
}

func maybeAppendPreflightAnalyzer(analyzers []*troubleshootv1beta2.HostAnalyze, analyzer *troubleshootv1beta2.HostAnalyze) []*troubleshootv1beta2.HostAnalyze {
	hostAnalyzer, _ := analyze.GetHostAnalyzer(analyzer)
	if hostAnalyzer == nil {
		return analyzers
	}
	for _, c := range analyzers {
		hc, _ := analyze.GetHostAnalyzer(c)
		if hc == nil {
			continue
		} else if hostAnalyzer.Title() == hc.Title() {
			return analyzers
		}
	}
	return append(analyzers, analyzer)
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
