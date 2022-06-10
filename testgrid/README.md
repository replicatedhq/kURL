# Testgrid
Testgrid is a an automation testing platform for kURL.
Testgrid installs kURL specs on a set of linux os versions and runs conformance tests.
## Testgrid components and Architecture
- Testgrid has three main components.
   - TGAPI: API is the main player that store and retrive the data to and from the database
   - Web: is the web interface for tests
   - TGrun: a daemon that polls the api for queued runs and starts new vms and tests.

![test-gride-architecture](./assets/testgride-architecture.drawio.png)
# Run Testgrid Locally
## Prerequests
- Have docker running locally
- Have some k8s cluster running
- Install [SchemaHero](https://schemahero.io/docs/installing/kubectl/)
- Install skaffold: https://skaffold.dev/docs/install/
- Set `GOOS` and `GOARCH`
```bash
   export GOOS=linux
   export GOARCH=amd64
```
## Run Testgride using skaffold
- Connect to the cluster
- Run the following command from ``TESTGRID`` path
```
make install
```

- Setup port-forwards
``` bash
kubectl port-forward svc/tgapi 30110:3000 &
kubectl port-forward svc/testgrid-web 30881:30881
```

- Now you are ready to do your first test. 

- From tgrun folder run the following command
```
./bin/tgrun queue --os-spec hack/os-spec.yaml --spec hack/test-spec.yaml --ref test-1 --api-token this-is-super-secret --api-endpoint http://localhost:30110
```

- From the web service you should be able to see the pending test.

- Now time to setup your runner by using ``terraform`` go indide the ``deploy` folder and follow the steps from the readme file.

# Run Testgrid on Okteto

1. Change directories to the root of the project
1. Run `okteto pipeline deploy -f testgrid/okteto-pipeline.yaml`
1. To "queue" a run `./bin/tgrun queue --os-spec hack/os-spec.yaml --spec hack/test-spec.yaml --ref ethan-1 --api-token this-is-super-secret --api-endpoint https://tgapi-${OKTETO_NAMESPACE}.replicated.okteto.dev`

# Support for multi node clusters

- Testgrid supports multi node clusters.
- You can achieve this by putting the following lines in specs file, adjusting the number of nodes as desired

```yaml
  numPrimaryNodes: 1
  numSecondaryNodes: 1
```

- The previous example will make the cluster run with one primary node and one secondary node. 


The process will be divided into three stages:
  
1. Main process before the actual node run

1. Initial primary node process

1. Normal nodes process (other primary and secondary nodes)  

## Main process

- The following chart explains what happens in the main process:

![flowchart-mainprocess](./assets/flowchart-mainprocess.png)

## InitPrimary node

The primary node can be in any one of the following statuses:

1. `running` when the VMI start

1. `JoincommandStored` when it does store the join command

1. `Success` when the test run successfully 

1. `Failed` when any steps during the test fail

The following chart explains what happens in the initial primary node:

![flowchart-initialprimarynode](./assets/flowchart-InitialPrimaryNode.png)

## Additional Nodes Flowchart

Additional nodes can be in the following status:

1. `Running` when the VMI starts

1. `WaitingJoinCommand` when waiting on the process to start

1. `Joined` When the node is joined successfully to the cluster

1. `Success` when the test runs successfully and the initial primary node finishes the test

1. `failed` when it fails to run any step

The following chart explains what happens in the normal node (secondary and normal primary nodes):

![flowchart-normalnode](./assets/flowchart-normalnode.png)
