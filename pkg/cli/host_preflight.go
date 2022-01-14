package cli

import (
	"context"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"regexp"
	"time"

	"github.com/briandowns/spinner"
	"github.com/mattn/go-isatty"
	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/pkg/installer"
	"github.com/replicatedhq/kurl/pkg/preflight"
	analyze "github.com/replicatedhq/troubleshoot/pkg/analyze"
	"github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
	troubleshootv1beta2 "github.com/replicatedhq/troubleshoot/pkg/apis/troubleshoot/v1beta2"
	"github.com/replicatedhq/troubleshoot/pkg/collect"
	"github.com/spf13/afero"
	"github.com/spf13/cobra"
)

const HostPreflightCmdExample = `
  # Installer spec from file
  $ kurl host preflight spec.yaml

  # Installer spec from STDIN
  $ kubectl get installer 6abe39c -oyaml | kurl host preflight -`

const (
	PREFLIGHTS_WARNING_CODE        = 3
	PREFLIGHTS_IGNORE_WARNING_CODE = 2
	PREFLIGHTS_ERROR_CODE          = 1
)

func NewHostPreflightCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:          "preflight [installer spec file|-]",
		Short:        "Runs kURL host preflight checks",
		Example:      HostPreflightCmdExample,
		SilenceUsage: true,
		Args:         cobra.ExactArgs(1),
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			v := cli.GetViper()

			installerSpecData, err := retrieveInstallerSpecDataFromArg(cli.GetFS(), cmd.InOrStdin(), args[0])
			if err != nil {
				return errors.Wrap(err, "retrieve installer spec from arg")
			}

			installerSpec, err := installer.DecodeSpec(installerSpecData)
			if err != nil {
				return errors.Wrap(err, "decode installer spec")
			}

			remotes := append([]string{}, v.GetStringSlice("primary-host")...)
			remotes = append(remotes, v.GetStringSlice("secondary-host")...)
			data := installer.TemplateData{
				Installer:      *installerSpec,
				IsPrimary:      v.GetBool("is-primary"),
				IsJoin:         v.GetBool("is-join"),
				IsUpgrade:      v.GetBool("is-upgrade"),
				PrimaryHosts:   v.GetStringSlice("primary-host"),
				SecondaryHosts: v.GetStringSlice("secondary-host"),
				RemoteHosts:    remotes,
			}

			preflightSpec := &troubleshootv1beta2.HostPreflight{}

			if !v.GetBool("exclude-builtin") {
				builtin := preflight.Builtin()
				s, err := decodePreflightSpec(builtin, data)
				if err != nil {
					return errors.Wrap(err, "builtin")
				}
				preflightSpec = s
			}

			for _, filename := range v.GetStringSlice("spec") {
				spec, err := ioutil.ReadFile(filename)
				if err != nil {
					return errors.Wrapf(err, "read spec file %s", filename)
				}

				decoded, err := decodePreflightSpec(string(spec), data)
				if err != nil {
					return errors.Wrap(err, filename)
				}

				preflightSpec.Spec.Collectors = append(preflightSpec.Spec.Collectors, decoded.Spec.Collectors...)
				preflightSpec.Spec.Analyzers = append(preflightSpec.Spec.Analyzers, decoded.Spec.Analyzers...)
			}

			if data.IsJoin && data.IsPrimary && !data.IsUpgrade {
				// Check connection to kubelet on all remotes
				for _, remote := range remotes {
					remote = formatAddress(remote)
					name := fmt.Sprintf("kubelet %s", remote)

					preflightSpec.Spec.Collectors = append(preflightSpec.Spec.Collectors, &v1beta2.HostCollect{
						TCPConnect: &v1beta2.TCPConnect{
							HostCollectorMeta: v1beta2.HostCollectorMeta{
								CollectorName: name,
							},
							Address: fmt.Sprintf("%s:10250", remote),
							Timeout: "5s",
						},
					})

					preflightSpec.Spec.Analyzers = append(preflightSpec.Spec.Analyzers, &v1beta2.HostAnalyze{
						TCPConnect: &v1beta2.TCPConnectAnalyze{
							AnalyzeMeta: v1beta2.AnalyzeMeta{
								CheckName: fmt.Sprintf("kubelet %s:10250 TCP connection status", remote),
							},
							CollectorName: name,
							Outcomes: []*v1beta2.Outcome{
								{
									Warn: &v1beta2.SingleOutcome{
										When:    collect.NetworkStatusConnectionRefused,
										Message: fmt.Sprintf("Connection to kubelet %s:10250 was refused", remote),
									},
								},
								{
									Warn: &v1beta2.SingleOutcome{
										When:    collect.NetworkStatusConnectionTimeout,
										Message: fmt.Sprintf("Timed out connecting to kubelet %s:10250", remote),
									},
								},
								{
									Warn: &v1beta2.SingleOutcome{
										When:    collect.NetworkStatusErrorOther,
										Message: fmt.Sprintf("Unexpected error connecting to kubelet %s:10250", remote),
									},
								},
								{
									Pass: &v1beta2.SingleOutcome{
										When:    collect.NetworkStatusConnected,
										Message: fmt.Sprintf("Successfully connected to kubelet %s:10250", remote),
									},
								},
							},
						},
					})
				}
				// Check connection to etcd on all primaries
				for _, primary := range data.PrimaryHosts {
					primary = formatAddress(primary)
					name := fmt.Sprintf("etcd peer %s", primary)

					preflightSpec.Spec.Collectors = append(preflightSpec.Spec.Collectors, &v1beta2.HostCollect{
						TCPConnect: &v1beta2.TCPConnect{
							HostCollectorMeta: v1beta2.HostCollectorMeta{
								CollectorName: name,
							},
							Address: fmt.Sprintf("%s:2380", primary),
							Timeout: "5s",
						},
					})

					preflightSpec.Spec.Analyzers = append(preflightSpec.Spec.Analyzers, &v1beta2.HostAnalyze{
						TCPConnect: &v1beta2.TCPConnectAnalyze{
							AnalyzeMeta: v1beta2.AnalyzeMeta{
								CheckName: fmt.Sprintf("etcd peer %s:2380 TCP connection status", primary),
							},
							CollectorName: name,
							Outcomes: []*v1beta2.Outcome{
								{
									Warn: &v1beta2.SingleOutcome{
										When:    collect.NetworkStatusConnectionRefused,
										Message: fmt.Sprintf("Connection to etcd peer %s:2380 was refused", primary),
									},
								},
								{
									Warn: &v1beta2.SingleOutcome{
										When:    collect.NetworkStatusConnectionTimeout,
										Message: fmt.Sprintf("Timed out connecting to etcd peer %s:2380", primary),
									},
								},
								{
									Warn: &v1beta2.SingleOutcome{
										When:    collect.NetworkStatusErrorOther,
										Message: fmt.Sprintf("Unexpected error connecting to etcd peer %s:2380", primary),
									},
								},
								{
									Pass: &v1beta2.SingleOutcome{
										When:    collect.NetworkStatusConnected,
										Message: fmt.Sprintf("Successfully connected to etcd peer %s:2380", primary),
									},
								},
							},
						},
					})
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

			if v.GetBool("use-exit-codes") {
				switch {
				case preflightIsFail(results):
					os.Exit(PREFLIGHTS_ERROR_CODE)
				case preflightIsWarn(results):
					if v.GetBool("ignore-warnings") {
						os.Exit(PREFLIGHTS_IGNORE_WARNING_CODE)
					} else {
						os.Exit(PREFLIGHTS_WARNING_CODE)
					}
				}
				return nil
			}

			switch {
			case preflightIsFail(results):
				return errors.New("preflights have failures")
			case preflightIsWarn(results):
				if v.GetBool("ignore-warnings") {
					fmt.Fprintln(cmd.ErrOrStderr(), "Warnings ignored by CLI flag \"ignore-warnings\"")
				} else {
					return ErrWarn
				}
			}
			return nil
		},
	}

	cmd.Flags().Bool("ignore-warnings", false, "ignore preflight warnings")
	cmd.Flags().Bool("is-join", false, "set to true if this node is joining an existing cluster (non-primary implies join)")
	cmd.Flags().Bool("is-primary", true, "set to true if this node is a primary")
	cmd.Flags().Bool("is-upgrade", false, "set to true if this is an upgrade")
	cmd.Flags().Bool("exclude-builtin", false, "set to true to exclude builtin preflights")
	cmd.Flags().Bool("use-exit-codes", true, "set to false to return an error instead of an exit code")
	cmd.Flags().StringSlice("primary-host", nil, "host or IP of a control plane node running a Kubernetes API server and etcd peer")
	cmd.Flags().StringSlice("secondary-host", nil, "host or IP of a secondary node running kubelet")
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

func retrieveInstallerSpecDataFromArg(fs afero.Fs, stdin io.Reader, arg string) ([]byte, error) {
	if arg == "-" {
		data, err := ioutil.ReadAll(stdin)
		if err != nil {
			return nil, errors.Wrap(err, "read from stdin")
		}
		if len(data) == 0 {
			return nil, errors.New("no data read from stdin")
		}
		return data, nil
	}

	data, err := afero.ReadFile(fs, arg)
	return data, errors.Wrapf(err, "read from file %s", arg)
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
