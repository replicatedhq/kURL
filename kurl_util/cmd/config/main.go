package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/pkg/errors"
	kurlversion "github.com/replicatedhq/kurl/pkg/version"
	kurlscheme "github.com/replicatedhq/kurlkinds/client/kurlclientset/scheme"
	kurlv1beta1 "github.com/replicatedhq/kurlkinds/pkg/apis/cluster/v1beta1"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/kubernetes/scheme"
)

func main() {
	utilruntime.Must(kurlscheme.AddToScheme(scheme.Scheme))

	version := flag.Bool("v", false, "Print version info")
	configType := flag.String("c", "", "config to process: selinux, iptables, firewalld")
	yamlPath := flag.String("y", "", "yaml file name with config info")
	execCmds := flag.Bool("e", false, "execute commands")
	generateScript := flag.Bool("g", false, "generate config script")

	flag.Parse()

	if *version {
		kurlversion.Print()
		return
	}

	if *configType == "" || *yamlPath == "" {
		flag.PrintDefaults()
		os.Exit(-1)
	}

	if !*execCmds && !*generateScript {
		flag.PrintDefaults()
		os.Exit(-1)
	}

	if err := processConfig(*configType, *yamlPath, *execCmds, *generateScript); err != nil {
		log.Fatal(err)
	}
}

func processConfig(configType string, yamlPath string, execCmds bool, generateScript bool) error {
	installer, err := installerFromFile(yamlPath)
	if err != nil {
		return errors.Wrap(err, "failed to load base config")
	}

	if installer == nil {
		return nil
	}

	switch configType {
	case "selinux":
		err := processSelinuxConfig(installer, execCmds, generateScript)
		return errors.Wrap(err, "failed to process selinux config")
	case "firewalld":
		err := processFirewalldConfig(installer, execCmds, generateScript)
		return errors.Wrap(err, "failed to process firewalld config")
	case "iptables":
		err := processIptablesConfig(installer, execCmds, generateScript)
		return errors.Wrap(err, "failed to process iptables config")
	default:
		return errors.Errorf("unknown config type: %s", configType)
	}
}

func installerFromFile(yamlPath string) (*kurlv1beta1.Installer, error) {
	yamlData, err := os.ReadFile(yamlPath)
	if err != nil {
		return nil, errors.Wrapf(err, "failed to load file %s", yamlPath)
	}

	yamlData = bytes.TrimSpace(yamlData)
	if len(yamlData) == 0 {
		return nil, nil
	}

	decode := scheme.Codecs.UniversalDeserializer().Decode
	obj, gvk, err := decode(yamlData, nil, nil)
	if err != nil {
		return nil, errors.Wrap(err, "failed to decode installer yaml")
	}

	if gvk.Group != "cluster.kurl.sh" || gvk.Version != "v1beta1" || gvk.Kind != "Installer" {
		return nil, errors.Errorf("installer yaml contained unepxected gvk: %s/%s/%s", gvk.Group, gvk.Version, gvk.Kind)
	}

	installer := obj.(*kurlv1beta1.Installer)

	return installer, nil
}

func processSelinuxConfig(installer *kurlv1beta1.Installer, execCmds bool, generateScript bool) error {
	scriptFilename := os.Getenv("CONFIGURE_SELINUX_SCRIPT")
	if scriptFilename == "" {
		scriptFilename = "./configure_selinux.sh" // for dev testing
	}

	if installer.Spec.SelinuxConfig == nil {
		// NOTE (ethan): I'm not sure the reason for this code.
		// I'm only trying not to change functionality.
		err := os.RemoveAll(scriptFilename)
		if err != nil && !os.IsNotExist(err) {
			log.Printf("Failed to delete %s: %v\n", scriptFilename, err)
		}
		return nil
	}

	deleteScript := true
	if generateScript && (installer.Spec.SelinuxConfig.Selinux != "" || installer.Spec.SelinuxConfig.Type != "") {
		scriptLines := []string{
			"BYPASS_SELINUX_PREFLIGHT=1",
		}

		switch installer.Spec.SelinuxConfig.Selinux {
		case "enforcing":
			scriptLines = append(scriptLines, "sed -i s/^SELINUX=.*$/SELINUX=enforcing/ /etc/selinux/config")
		case "permissive":
			scriptLines = append(scriptLines, "setenforce 0")
			scriptLines = append(scriptLines, "sed -i s/^SELINUX=.*$/SELINUX=permissive/ /etc/selinux/config")
		case "disabled":
			scriptLines = append(scriptLines, "setenforce 0")
			scriptLines = append(scriptLines, "sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config")
		case "":
		default:
			return errors.Errorf("unknown selinux option: %s", installer.Spec.SelinuxConfig.Selinux)
		}
		if installer.Spec.SelinuxConfig.Type != "" {
			line := fmt.Sprintf("sed -i s/^SELINUXTYPE=.*$/SELINUXTYPE=%s/ /etc/selinux/config", installer.Spec.SelinuxConfig.Type)
			scriptLines = append(scriptLines, line)
		}
		if installer.Spec.SelinuxConfig.Selinux == "enforcing" {
			// this always has to be at the end of the script or all other commands will fail
			scriptLines = append(scriptLines, "setenforce 1")
		}

		script := fmt.Sprintf("configure_selinux() {\n\t%s\n}", strings.Join(scriptLines, "\n\t"))
		if err := writeScript(scriptFilename, script); err != nil {
			return errors.Wrap(err, "faied to save script")
		}
		deleteScript = false
	}

	if execCmds {
		for _, args := range installer.Spec.SelinuxConfig.ChconCmds {
			err := runCommand("chcon", args)
			if err != nil {
				return errors.Wrap(err, "failed to run chcon")
			}
		}
		for _, args := range installer.Spec.SelinuxConfig.SemanageCmds {
			err := runCommand("semanage", args)
			if err != nil {
				return errors.Wrap(err, "failed to run semanage")
			}
		}
	}

	if deleteScript {
		err := os.RemoveAll(scriptFilename)
		if err != nil && !os.IsNotExist(err) {
			log.Printf("Failed to delete %s: %v\n", scriptFilename, err)
		}
	}

	return nil
}

func processFirewalldConfig(installer *kurlv1beta1.Installer, execCmds bool, generateScript bool) error {
	scriptFilename := os.Getenv("CONFIGURE_FIREWALLD_SCRIPT")
	if scriptFilename == "" {
		scriptFilename = "./configure_firewalld.sh" // for dev testing
	}

	if installer.Spec.FirewalldConfig == nil {
		// NOTE (ethan): I'm not sure the reason for this code.
		// I'm only trying not to change functionality.
		err := os.RemoveAll(scriptFilename)
		if err != nil && !os.IsNotExist(err) {
			log.Printf("Failed to delete %s: %v\n", scriptFilename, err)
		}
		return nil
	}

	deleteScript := true
	if generateScript && installer.Spec.FirewalldConfig.Firewalld != "" {
		scriptLines := []string{
			"BYPASS_FIREWALLD_WARNING=1",
		}

		switch installer.Spec.FirewalldConfig.Firewalld {
		case "enabled":
			scriptLines = append(scriptLines, "systemctl start firewalld")
			scriptLines = append(scriptLines, "systemctl enable firewalld")
		case "disabled":
			scriptLines = append(scriptLines, "if ! systemctl -q is-active firewalld ; then")
			scriptLines = append(scriptLines, "	return")
			scriptLines = append(scriptLines, "fi")
			scriptLines = append(scriptLines, "systemctl stop firewalld")
			scriptLines = append(scriptLines, "systemctl disable firewalld")
		default:
			return errors.Errorf("unknown firewalld option: %s", installer.Spec.FirewalldConfig.Firewalld)
		}

		script := fmt.Sprintf("configure_firewalld() {\n\t%s\n}", strings.Join(scriptLines, "\n\t"))
		if err := writeScript(scriptFilename, script); err != nil {
			return errors.Wrap(err, "faied to save script")
		}
		deleteScript = false
	}

	if execCmds {
		for _, args := range installer.Spec.FirewalldConfig.FirewalldCmds {
			err := runCommand("firewall-cmd", args)
			if err != nil {
				return errors.Wrap(err, "failed to run firewall-cmd")
			}
		}
	}

	if deleteScript {
		err := os.RemoveAll(scriptFilename)
		if err != nil && !os.IsNotExist(err) {
			log.Printf("Failed to delete %s: %v\n", scriptFilename, err)
		}
	}

	return nil
}

func processIptablesConfig(installer *kurlv1beta1.Installer, execCmds bool, _ bool) error {
	if installer.Spec.IptablesConfig == nil {
		return nil
	}

	if execCmds {
		for _, args := range installer.Spec.IptablesConfig.IptablesCmds {
			err := runCommand("iptables", args)
			if err != nil {
				return errors.Wrap(err, "failed to run iptables")
			}
		}
	}
	return nil
}

func writeScript(filename string, script string) error {
	err := os.MkdirAll(filepath.Dir(filename), 0755)
	if err != nil {
		return errors.Wrap(err, "failed to create script dir")
	}

	f, err := os.OpenFile(filename, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0755)
	if err != nil {
		return errors.Wrap(err, "failed to create script file")
	}
	defer f.Close()

	_, err = f.WriteString(script)
	if err != nil {
		return errors.Wrap(err, "failed to write script file")
	}

	return nil
}

func runCommand(command string, args []string) error {
	log.Printf("Running %s %v", command, args)
	cmd := exec.CommandContext(context.Background(), command, args...)

	output, err := cmd.CombinedOutput()
	if len(output) > 0 {
		log.Printf("%s", output)
	}

	if err != nil {
		return errors.Wrap(err, "failed to execute command")
	}

	return nil
}
