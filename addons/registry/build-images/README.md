
# s3cmd

```bash
image=addons/registry/build-images/s3cmd
curl -H "Authorization: token $GH_PAT" \
  -H 'Accept: application/json' \
  -d "{\"event_type\": \"build-image\", \"client_payload\": {\"image\": \"${image}\"}}" \
  "https://api.github.com/repos/replicatedhq/kurl/dispatches"
```
