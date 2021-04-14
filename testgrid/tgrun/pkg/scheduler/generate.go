package scheduler

var kubernetesVersions = []string{
	"1.17.3",
	// "1.16.4",
}

var cri = map[string][]string{
	"docker": []string{
		"19.03.4",
		// "18.09.8",
	},
}

var cni = map[string][]string{
	"weave": []string{
		"1.0.4",
	},
	// "calico": []string{
	// 	"3.9.1",
	// },
}

var addOnsWithVersions = map[string][]string{
	// "aws": []string{
	// 	// "0.0.1",
	// },
	"contour": []string{
		"1.0.1",
		// "0.14.0",
	},
	"ekco": []string{
		"0.2.4",
		// "0.2.3",
		// "0.2.2",
		// "0.2.1",
		// "0.1.0",
	},
	// "fluentd": []string{
	// 	"1.7.4",
	// },
	"rook": []string{
		"1.0.4",
	},
	"prometheus": []string{
		"0.33.0",
	},
	"kotsadm": []string{
		"1.16.0",
		// "1.15.5",
		// "1.15.4",
		// "1.15.3",
		// "1.15.2",
		// "1.15.1",
		// "1.15.0",
	},
	"minio": []string{
		"2020-01-25T02-50-51Z",
	},
	// "nodeless": []string{},
	// "openebs": []string{
	// 	"1.6.0",
	// },
	"registry": []string{
		"2.7.1",
	},
	"velero": []string{
		"1.2.0",
	},
}

// func RunGenerated(ref string) error {

// 	// generate a kURL spec for each configuratino
// 	allTests, err := generateAllAddOns()
// 	if err != nil {
// 		panic(err)
// 	}

// 	deduplicated := map[string]kurlv1beta1.InstallerSpec{}

// 	for _, t := range allTests {
// 		b, err := json.Marshal(t)
// 		if err != nil {
// 			panic(err)
// 		}

// 		deduplicated[fmt.Sprintf("%x", sha256.Sum256(b))] = t
// 	}

// 	allTests = []kurlv1beta1.InstallerSpec{}
// 	for _, t := range deduplicated {
// 		allTests = append(allTests, t)
// 	}

// 	toTest := []kurlv1beta1.InstallerSpec{}

// 	for _, kubernetesVersion := range kubernetesVersions {
// 		installerSpec := kurlv1beta1.InstallerSpec{
// 			Kubernetes: kurlv1beta1.Kubernetes{
// 				Version: kubernetesVersion,
// 			},
// 		}

// 		for criName, criVersions := range cri {
// 			for _, criVersion := range criVersions {
// 				if criName == "docker" {
// 					installerSpec.Docker = kurlv1beta1.Docker{
// 						Version: criVersion,
// 					}
// 				} else {
// 					panic("unknown cri")
// 				}

// 				for cniName, cniVersions := range cni {
// 					for _, cniVersion := range cniVersions {
// 						if cniName == "weave" {
// 							installerSpec.Weave = kurlv1beta1.Weave{
// 								Version: cniVersion,
// 							}
// 						} else if cniName == "calico" {
// 							installerSpec.Calico = kurlv1beta1.Calico{
// 								Version: cniVersion,
// 							}
// 						} else {
// 							panic("unknown cni")
// 						}

// 						fmt.Printf("generating specs for kubernetes %s with %s@%s and %s@%s\n", kubernetesVersion, criName, criVersion, cniName, cniVersion)

// 						// now we need to get compbinations of all addons

// 						toTest = append(toTest, allTests...)

// 					}
// 				}
// 			}
// 		}

// 	}

// 	// deduplicate because of

// 	fmt.Printf("there are %d tests to execute on each OS\n", len(toTest))

// 	return nil
// }
