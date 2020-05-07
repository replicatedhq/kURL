# Add-On Compatibility and Conflicts

This proposal defines a set of categories that add-ons can belong to and assigns each add-on to one or more categories.
It also defines the dependencies of each add-on.

## Goals

- Offer high-level guidance to authors of kURL specs about which add-ons to include in their installer.
- Decrease the likelihood of designing kURL specs that result in non-functioning installations.

## Non Goals

- Detecting syntax and low-level errors within the configurations of individual add-ons.

## Background

Authors of kURL specs must select from a growing list of add-ons.
They may not be familiar with the function of the add-on and may not be aware of its dependencies.
Authors must spend time researching each add-on and try installations to verify their spec results in a working cluster.

A better experience would be to provide guidance that would lead to working clusters by default.

## High-Level Design

Each add-on belongs to one or more of the following categories:

- "Container Runtime"
- "CNI Plugin"
- "PVC Provisioner"
- "Object Store"
- "Ingress"
- "Logs"
- "Snapshots"
- "Metrics & Monitoring"
- "Cluster Administration"
- "Application Management"

Each add-on can specify dependencies on other categories.

Add-ons belonging to the same category conflict with each other.

## Detailed Design

Add a GET /add-ons endpoint that returns a list of add-ons along with their dependencies, what categories the add-on belongs to, and any other add-ons that are recommended to enable all features.
Example response:

```
[
	{
		name: "docker",
		fulfills: ["Container Runtime"],
		requires: [],
		recommends: [],
	},{
		name: "containerd",
		fulfilles: ["Container Runtime"],
		requires: [],
		recommends: [],
	},{
		name: "weave",
		fulfills: ["CNI Plugin"],
		requires: ["Container Runtime"],
		recommends: [],
	},{
		name: "calico",
		fulfills: ["CNI Plugin"],
		requires: ["Container Runtime"],
		recommends: [],
	},{
		name: "rook",
		fulfills: ["PVC Provisioner", "Object Store"],
		requires: ["CNI Plugin", "Container Runtime"],
		recommends: ["ekco"],
	},{
		name: "openEBS",
		fulfills: ["PVC Provisioner"],
		requires: ["CNI Plugin", "Container Runtime"],
		recommends: [],
	},{
		name: "minio",
		fulfills: ["Object Store"],
		requires: ["CNI Plugin", "Container Runtime"],
		recommends: [],
	},{
		name: "contour",
		fulfills: ["Ingress"],
		requires: ["CNI Plugin", "Container Runtime"],
		recommends: [],
	},{
		name: "fluentd",
		fulfills: ["Logs"],
		requires: ["CNI Plugin", "Container Runtime"],
		recommends: [],
	},{
		name: "kotsadm",
		fulfills: ["Application Management"],
		requires: ["CNI Plugin", "Container Runtime", "PVC Provisioner", "Object Store"],
		recommends: ["registry", "velero"],
	},{
		name: "registry",
		fulfills: ["Registry"],
		requires: ["CNI Plugin", "Container Runtime","Object Store"],
		recommends: [],
	},{
		name: "velero",
		fulfills: ["Snapshots"],
		requires: ["CNI Plugin", "Container Runtime", "Object Store"],
		recommends: [],
	},{
		name: "prometheus",
		fulfills: ["Metrics & Monitoring"],
		requires: ["CNI Plugin", "Container Runtime", "PVC Provisioner"],
		recommends: [],
	},{
		name: "ekco",
		fulfills: ["Cluster Administration"],
		requires: ["CNI Plugin", "Container Runtime"],
		recommends: [],
	}
]
```

Each addon root directory may have a categories.json file that defines an object representing the add-on.
The addon/<version> directories do not have separate categories.json files.
Add a Node script to bin/ that will read all the categories.json files, concatenate them into an array, and output the result as json.
In the deploy-staging GitHub workflow, call the Node script, save the output to a tmp file, and upload the output to the S3 staging folder.
Do the same for the prod script.
Clients will then be able to GET the file from either https://kurl.sh/dist/add-ons.json or https://kurl-sh.s3.amazonaws.com/dist/add-ons.json.

## Alternatives Considered

### Detailed Conflicts

It's possible to use more than 1 add-on from the same category together.
For example, rook can be used with openEBS if openEBS is configured to use non-default StorageClasses.
But for the majority of authors at the add-on selection stage, including both PVC provisioners would be due to misunderstanding.

## Security Considerations

None
