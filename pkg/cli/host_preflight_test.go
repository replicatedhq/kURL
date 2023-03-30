package cli

import (
	"bytes"
	"io"
	"testing"

	"github.com/golang/mock/gomock"
	mock_cli "github.com/replicatedhq/kurl/pkg/cli/mock"
	mock_preflight "github.com/replicatedhq/kurl/pkg/preflight/mock"
	analyze "github.com/replicatedhq/troubleshoot/pkg/analyze"
	"github.com/spf13/afero"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var installerYAML = `apiVersion: cluster.kurl.sh/v1beta1
kind: Installer
metadata:
  name: basic
spec:
  kubernetes:
    version: 1.18.10`

func TestNewHostPreflightCmd(t *testing.T) {
	tests := []struct {
		name           string
		installerYAML  string
		analyzeResults []*analyze.AnalyzeResult
		isWarn         bool
		ignoreWarnings bool
		isFail         bool
		stdout         string
		stderr         string
		wantErr        bool
	}{
		{
			name:          "pass",
			installerYAML: installerYAML,
			analyzeResults: []*analyze.AnalyzeResult{
				{
					Title:   "Number of CPUs",
					Message: "At least 4 CPU cores are required",
					IsPass:  true,
				},
			},
			stdout: OutputPassGreen() + " Number of CPUs: At least 4 CPU cores are required\n",
			stderr: "",
		},
		{
			name:          "warn",
			installerYAML: installerYAML,
			analyzeResults: []*analyze.AnalyzeResult{
				{
					Title:   "Number of CPUs",
					Message: "At least 4 CPU cores are required",
					IsWarn:  true,
				},
			},
			isWarn:  true,
			stdout:  OutputWarnYellow() + " Number of CPUs: At least 4 CPU cores are required\n",
			stderr:  "Error: host preflights have warnings\n",
			wantErr: true,
		},
		{
			name:          "warn ignore",
			installerYAML: installerYAML,
			analyzeResults: []*analyze.AnalyzeResult{
				{
					Title:   "Number of CPUs",
					Message: "At least 4 CPU cores are required",
					IsWarn:  true,
				},
			},
			isWarn:         true,
			ignoreWarnings: true,
			stdout:         OutputWarnYellow() + " Number of CPUs: At least 4 CPU cores are required\n",
			stderr:         "Warnings ignored by CLI flag \"ignore-warnings\"\n",
		},
		{
			name:          "fail",
			installerYAML: installerYAML,
			analyzeResults: []*analyze.AnalyzeResult{
				{
					Title:   "Number of CPUs",
					Message: "At least 4 CPU cores are required",
					IsFail:  true,
				},
			},
			isFail: true,
			stdout: OutputFailRed() + " Number of CPUs: At least 4 CPU cores are required\n",
			stderr: "Error: host preflights have failures\n",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockCtrl := gomock.NewController(t)
			defer mockCtrl.Finish()

			installerFilename := "/tmp/installer.yaml"

			fs := afero.NewMemMapFs()
			err := afero.WriteFile(fs, installerFilename, []byte(tt.installerYAML), 0666)
			require.NoError(t, err)

			mockPreflightRunner := mock_preflight.NewMockRunnerHost(mockCtrl)
			mockPreflightRunner.EXPECT().
				RunHostPreflights(gomock.Any(), gomock.Any(), gomock.Any()).
				Return(tt.analyzeResults, error(nil)).
				Times(1)

			v := viper.New()

			mockCLI := mock_cli.NewMockCLI(mockCtrl)
			mockCLI.EXPECT().
				GetViper().
				Return(v).
				Times(3)
			mockCLI.EXPECT().
				GetFS().
				Return(fs).
				Times(1)
			mockCLI.EXPECT().
				GetHostPreflightRunner().
				Return(mockPreflightRunner).
				Times(1)

			cmd := newHostPreflightCmd(mockCLI)

			bOut, bErr := bytes.NewBufferString(""), bytes.NewBufferString("")
			cmd.SetOut(bOut)
			cmd.SetErr(bErr)
			args := []string{installerFilename, "--use-exit-codes=false"}
			if tt.ignoreWarnings {
				args = append(args, "--ignore-warnings")
			}
			cmd.SetArgs(args)

			err = cmd.Execute()
			if tt.isFail {
				assert.EqualError(t, err, "host preflights have failures")
			} else if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}

			stdout, err := io.ReadAll(bOut)
			require.NoError(t, err)

			stderr, err := io.ReadAll(bErr)
			require.NoError(t, err)

			assert.Equal(t, tt.stdout, string(stdout))
			if tt.ignoreWarnings {
				assert.Equal(t, "Warnings ignored by CLI flag \"ignore-warnings\"\n", string(stderr))
			} else {
				assert.Equal(t, tt.stderr, string(stderr))
			}
		})
	}
}

func TestNewClusterPreflightCmd(t *testing.T) {
	tests := []struct {
		name           string
		installerYAML  string
		analyzeResults []*analyze.AnalyzeResult
		isWarn         bool
		ignoreWarnings bool
		isFail         bool
		stdout         string
		stderr         string
		wantErr        bool
	}{
		{
			name:          "pass",
			installerYAML: installerYAML,
			analyzeResults: []*analyze.AnalyzeResult{
				{
					Title:   "Node status check",
					Message: "All nodes are online",
					IsPass:  true,
				},
			},
			stdout: OutputPassGreen() + " Node status check: All nodes are online\n",
			stderr: "",
		},
		{
			name:          "warn",
			installerYAML: installerYAML,
			analyzeResults: []*analyze.AnalyzeResult{
				{
					Title:   "Number of CPUs",
					Message: "At least 4 CPU cores are required",
					IsWarn:  true,
				},
			},
			isWarn:  true,
			stdout:  OutputWarnYellow() + " Number of CPUs: At least 4 CPU cores are required\n",
			stderr:  "Error: host preflights have warnings\n",
			wantErr: true,
		},
		{
			name:          "warn ignore",
			installerYAML: installerYAML,
			analyzeResults: []*analyze.AnalyzeResult{
				{
					Title:   "Number of CPUs",
					Message: "At least 4 CPU cores are required",
					IsWarn:  true,
				},
			},
			isWarn:         true,
			ignoreWarnings: true,
			stdout:         OutputWarnYellow() + " Number of CPUs: At least 4 CPU cores are required\n",
			stderr:         "Warnings ignored by CLI flag \"ignore-warnings\"\n",
		},
		{
			name:          "fail",
			installerYAML: installerYAML,
			analyzeResults: []*analyze.AnalyzeResult{
				{
					Title:   "Number of CPUs",
					Message: "At least 4 CPU cores are required",
					IsFail:  true,
				},
			},
			isFail: true,
			stdout: OutputFailRed() + " Number of CPUs: At least 4 CPU cores are required\n",
			stderr: "Error: preflights have failures\n",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockCtrl := gomock.NewController(t)
			defer mockCtrl.Finish()

			installerFilename := "/tmp/installer.yaml"

			fs := afero.NewMemMapFs()
			err := afero.WriteFile(fs, installerFilename, []byte(tt.installerYAML), 0666)
			require.NoError(t, err)

			mockPreflightRunner := mock_preflight.NewMockRunnerCluster(mockCtrl)
			mockPreflightRunner.EXPECT().
				RunClusterPreflight(gomock.Any(), gomock.Any()).
				Return(tt.analyzeResults, error(nil)).
				Times(1)

			v := viper.New()

			mockCLI := mock_cli.NewMockCLI(mockCtrl)
			mockCLI.EXPECT().
				GetViper().
				Return(v).
				Times(3)
			mockCLI.EXPECT().
				GetFS().
				Return(fs).
				Times(1)
			mockCLI.EXPECT().
				GetClusterPreflightRunner().
				Return(mockPreflightRunner).
				Times(1)

			cmd := newPreflightCmd(mockCLI)

			bOut, bErr := bytes.NewBufferString(""), bytes.NewBufferString("")
			cmd.SetOut(bOut)
			cmd.SetErr(bErr)
			args := []string{installerFilename, "--use-exit-codes=false"}
			if tt.ignoreWarnings {
				args = append(args, "--ignore-warnings")
			}
			cmd.SetArgs(args)

			err = cmd.Execute()
			if tt.isFail {
				assert.EqualError(t, err, "preflights have failures")
			} else if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}

			stdout, err := io.ReadAll(bOut)
			require.NoError(t, err)

			stderr, err := io.ReadAll(bErr)
			require.NoError(t, err)

			assert.Equal(t, tt.stdout, string(stdout))
			if tt.ignoreWarnings {
				assert.Equal(t, "Warnings ignored by CLI flag \"ignore-warnings\"\n", string(stderr))
			} else {
				assert.Equal(t, tt.stderr, string(stderr))
			}
		})
	}
}
