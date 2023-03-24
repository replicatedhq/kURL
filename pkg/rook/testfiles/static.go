package testfiles

import _ "embed"

// for health unit tests

//go:embed healthyCephStatus1.json
var HealthyCephStatus1 []byte

//go:embed rebalanceCephStatus1.json
var RebalanceCephStatus1 []byte

//go:embed rebalanceCephStatus2.json
var RebalanceCephStatus2 []byte

//go:embed rebalanceCephStatusFull.json
var RebalanceCephStatusFull []byte

//go:embed rebalanceCephStatusMultinode.json
var RebalanceCephStatusMultinode []byte

//go:embed tooManyPgsPerOsd.json
var TooManyPGSPerOSD []byte

//go:embed autoscalerCephStatus.json
var AutoscalerInProgressCephStatus []byte

//go:embed noreplicasCephStatus.json
var NoReplicasCephStatus []byte

//go:embed poolPgNumNotPowerOfTwoCephStatus.json
var PoolPgNumNotPowerOfTwoCephStatus []byte

//go:embed recentCrashCephStatus.json
var RecentCrashCephStatus []byte

//go:embed globalRecoveryEventCephStatus.json
var GlobalRecoveryEventStatus []byte

//go:embed hypotheticalCheckHealthWarnCephStatus.json
var HypotheticalCheckHealthWarnCephStatus []byte

// lists of pods to use in migrate unit tests

//go:embed "6 blockdevice pods.json"
var SixBlockDevicePods []byte

//go:embed "hostpathpods.json"
var HostpathPods []byte

// lists of deployments to be used in toolbox unit tests

//go:embed "rook-6osd-deployments.json"
var Rook6OSDDeployments []byte

//go:embed "rook-hostpath-deployments.json"
var RookHostpathDeployments []byte

// lists of nodes to be used in unit tests

//go:embed "upgradedNode.json"
var UpgradedNode []byte

//go:embed "upgradedNodeLess50Images.json"
var UpgradedNodeLess50Images []byte

//go:embed "waitForRookVersionAllReady.json"
var WaitForRookVersionAllReady []byte

//go:embed "waitForRookVersionAllReady.json"
var WaitForRookVersionAllReadyWithEmptyVersion []byte

//go:embed "waitForRookVersionOldVersions.json"
var WaitForRookVersionOldVersions []byte

//go:embed "waitForRookVersionNotReady.json"
var WaitForRookVersionNotReady []byte

//go:embed "scalePodOwnerDeploy.json"
var ScalePodOwnerDeploy []byte

//go:embed "scalePodOwnerSts.json"
var ScalePodOwnerSts []byte

//go:embed "listPVCsByStorageClass.json"
var ListPVCsByStorageClass []byte
