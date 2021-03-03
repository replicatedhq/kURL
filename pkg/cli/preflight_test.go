package cli

import (
	"bytes"
	"io/ioutil"
	"testing"

	"github.com/chzyer/readline"
	"github.com/golang/mock/gomock"
	mock_cli "github.com/replicatedhq/kurl/pkg/cli/mock"
	mock_preflight "github.com/replicatedhq/kurl/pkg/preflight/mock"
	analyze "github.com/replicatedhq/troubleshoot/pkg/analyze"
	"github.com/spf13/afero"
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

func TestNewPreflightCmd(t *testing.T) {
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
			stdout: "[PASS] Number of CPUs: At least 4 CPU cores are required\n",
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
			isWarn: true,
			stdout: "[WARN] Number of CPUs: At least 4 CPU cores are required\n",
			stderr: "",
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
			stdout:         "[WARN] Number of CPUs: At least 4 CPU cores are required\n",
			stderr:         "",
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
			stdout: "[FAIL] Number of CPUs: At least 4 CPU cores are required\n",
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

			mockPreflightRunner := mock_preflight.NewMockRunner(mockCtrl)
			mockPreflightRunner.EXPECT().
				Run(gomock.Any(), gomock.Any(), gomock.Any()).
				Return(tt.analyzeResults, error(nil)).
				Times(1)

			mockCLI := mock_cli.NewMockCLI(mockCtrl)
			mockCLI.EXPECT().
				GetFS().
				Return(fs).
				Times(1)
			mockCLI.EXPECT().
				GetPreflightRunner().
				Return(mockPreflightRunner).
				Times(1)
			if tt.isWarn && !tt.ignoreWarnings {
				rl, err := readline.New("")
				require.NoError(t, err)
				mockCLI.EXPECT().
					GetReadline().
					Return(rl).
					Times(1)
			}

			cmd := NewPreflightCmd(mockCLI)

			bOut, bErr := bytes.NewBufferString(""), bytes.NewBufferString("")
			cmd.SetOut(bOut)
			cmd.SetErr(bErr)
			args := []string{installerFilename}
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

			stdout, err := ioutil.ReadAll(bOut)
			require.NoError(t, err)

			stderr, err := ioutil.ReadAll(bErr)
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
