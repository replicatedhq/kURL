package scheduler

import (
	"fmt"
	"sort"
	"strings"

	kurlv1beta1 "github.com/replicatedhq/kurl/kurlkinds/pkg/apis/cluster/v1beta1"
)

func generateAllAddOns() ([]kurlv1beta1.InstallerSpec, error) {
	installerSpecs := []kurlv1beta1.InstallerSpec{}

	installerSpec := kurlv1beta1.InstallerSpec{}

	for addOnName, addOnVersions := range addOnsWithVersions {
		for _, addOnVersion := range addOnVersions {
			// for this addon, get all compbinations of others
			fmt.Printf("generating possible addons for %s@%s\n", addOnName, addOnVersion)
			withAddOn, err := appendAddOnToInstallerSpec(installerSpec, addOnName, addOnVersion)
			if err != nil {
				return nil, err
			}

			allInstallerSpecs, err := generateAllAddOnsExcept(withAddOn, []string{addOnName})
			if err != nil {
				return nil, err
			}

			installerSpecs = append(installerSpecs, allInstallerSpecs...)
		}
	}

	return installerSpecs, nil
}

func generateAllAddOnsExcept(installerSpec kurlv1beta1.InstallerSpec, withoutAddOnNames []string) ([]kurlv1beta1.InstallerSpec, error) {
	sort.Strings(withoutAddOnNames)
	joined := strings.Join(withoutAddOnNames, ",")
	for _, previouslyGeneratedName := range previouslyGeneratedNames {
		if previouslyGeneratedName == joined {
			return []kurlv1beta1.InstallerSpec{}, nil
		}
	}

	previouslyGeneratedNames = append(previouslyGeneratedNames, joined)

	installerSpecs := []kurlv1beta1.InstallerSpec{}

	for addOnName, addOnVersions := range addOnsWithVersions {
		excluded := false
		for _, withoutAddOnName := range withoutAddOnNames {
			if addOnName == withoutAddOnName {
				excluded = true
			}
		}
		if excluded {
			installerSpecs = append(installerSpecs, installerSpec)
			continue
		}

		without := append([]string{}, withoutAddOnNames...)
		without = append(without, addOnName)

		specs, err := generateAllAddOnsExcept(installerSpec, without)
		if err != nil {
			return nil, err
		}

		for _, addOnVersion := range addOnVersions {
			for _, spec := range specs {
				updatedInstallerSpec, err := appendAddOnToInstallerSpec(spec, addOnName, addOnVersion)
				if err != nil {
					return nil, err
				}

				installerSpecs = append(installerSpecs, updatedInstallerSpec)
			}
		}
	}

	return installerSpecs, nil
}

func appendAddOnToInstallerSpec(installerSpec kurlv1beta1.InstallerSpec, addOnName string, addOnVersion string) (kurlv1beta1.InstallerSpec, error) {
	switch addOnName {

	case "contour":
		installerSpec.Contour = kurlv1beta1.Contour{
			Version: addOnVersion,
		}

	case "ekco":
		installerSpec.Ekco = kurlv1beta1.Ekco{
			Version: addOnVersion,
		}

	case "fluentd":
		installerSpec.Fluentd = kurlv1beta1.Fluentd{
			Version: addOnVersion,
		}

	case "rook":
		installerSpec.Rook = kurlv1beta1.Rook{
			Version: addOnVersion,
		}

	case "prometheus":
		installerSpec.Prometheus = kurlv1beta1.Prometheus{
			Version: addOnVersion,
		}

	case "kotsadm":
		installerSpec.Kotsadm = kurlv1beta1.Kotsadm{
			Version: addOnVersion,
		}

	case "minio":
		installerSpec.Minio = kurlv1beta1.Minio{
			Version: addOnVersion,
		}

	case "openebs":
		installerSpec.OpenEBS = kurlv1beta1.OpenEBS{
			Version: addOnVersion,
		}

	case "registry":
		installerSpec.Registry = kurlv1beta1.Registry{
			Version: addOnVersion,
		}

	case "velero":
		installerSpec.Velero = kurlv1beta1.Velero{
			Version: addOnVersion,
		}

	default:
		panic("unknown add on")
	}

	return installerSpec, nil
}
