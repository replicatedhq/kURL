# TestGride
Testgrid is a an automation testing platform for kurl.
Testgrid spins up vms and installs kurl + kubernetes and runs conformance tests.
## TestGride components and Architecture
- TestGride has three main components.
   - TGAPI: API is the main player that store and retrive the data to and from the database
   - Web: is the web interface for tests
   - TGrun: runner that pull the queued tests and start to test them

![test-gride-architecture](./assets/testgride-architecture.drawio.png)
# Run Testgrid local
## Prerequests
- Have docker running locally
- Have some k8s cluster running
- Install [SchemaHero](https://schemahero.io/docs/installing/kubectl/)
- Set `GOOS` and `GOARCH`
```bash
   export GOOS=linux
   export GOARCH=amd64
```
## Run Testgride using skaffold
- If you are using ``longhorn`` to provision the PVC you will need to do the following changes to ``web`` service

  1- Change the port in the ``Dockerfile.skaffold`` to ``30881`` as port ``30880`` is used by ``longhorn``
  2- In ``webpack.dev.config.js`` file change the port in the following code to be ``30881`` instead 0f ``8080``
  ```
  devServer: {
    port: 8080,
    host: "0.0.0.0",
    hot: true,
    hotOnly: true,
    historyApiFallback: {
      verbose: true,
    },
    disableHostCheck: true,
  },
  ```
  3- In env/development.js file make sure to use the localhost domain for the API as we will do port-forward later to the localhost
  ```
   API_ENDPOINT: `http://localhost:{port}/api/v1`
  ```

- Build tgapi: `(cd tgapi && make build)`

- Build tgrun: `(cd tgrun && make build)`

- Install skaffold: https://skaffold.dev/docs/install/

- From the TESTGRID folder run the following command
```bash
skaffold run --default-repo ttl.sh/yourname-testgrid
```
- This might take time

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
