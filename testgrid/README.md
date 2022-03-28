# Run Testgrid local

1. Have docker running locally
1. Have some k8s cluster running
1. Install [SchemaHero](https://schemahero.io/docs/installing/kubectl/)
1. Set `GOOS` and `GOARCH`
   ```
   export GOOS=linux
   export GOARCH=amd64
   ``` 
1. Build tgapi: `(cd tgapi && make build)`
1. Build tgrun: `(cd tgrun && make build)`
1. Build web: `(cd web && make build-staging)` - This will fail. Not sure if needed.
1. Install skaffold: `brew install skaffold`
1. `skaffold run --default-repo ttl.sh/yourname-testgrid` - This takes time! Go make some coffee. Throw something on your bbq smoker. Go talk to your neighbour!
1. Setup port-forwards `kubectl port-forward svc/testgrid-web 30880:30880` and `kubectl port-forward svc/tgapi 30110:3000`
1. Insert some data in the postgres db
   ```
   INSERT INTO public.testrun(
	ref, created_at)
	VALUES (1, '2022-02-21 19:10:25-07');
   INSERT INTO public.testinstance(
	id, testrun_ref, enqueued_at, dequeued_at, started_at, running_at, finished_at, is_success, failure_reason, is_unsupported, output, sonobuoy_results, kurl_yaml, kurl_url, kurl_flags, os_name, os_version, os_image, os_preinit)
	VALUES (1, 1, '2022-02-21 19:10:25-07', '2022-02-21 19:10:25-07', '2022-02-21 19:10:25-07', '2022-02-21 19:10:25-07', '2022-02-21 19:10:25-07', true, 'none', false, 'something', 'whoknows', '{"testing":"value"}', 'someurl', 'mylabels', 'rhel', '8.x', 'rhel', 'somepreinit');
   ```

# Run Testgrid on Okteto

1. Change directories to the root of the project
1. Run `okteto pipeline deploy -f testgrid/okteto-pipeline.yaml`
1. To "queue" a run `./bin/tgrun queue --os-spec hack/os-spec.yaml --spec hack/test-spec.yaml --ref ethan-1 --api-token this-is-super-secret --api-endpoint https://tgapi-${OKTETO_NAMESPACE}.replicated.okteto.dev`
