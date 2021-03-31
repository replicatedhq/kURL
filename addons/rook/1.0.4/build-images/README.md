
# ceph

```bash
image=addons/rook/1.0.4/build-images/ceph
curl -H "Authorization: token $GH_PAT" \
  -H 'Accept: application/json' \
  -d "{\"event_type\": \"build-image\", \"client_payload\": {\"image\": \"${image}\"}}" \
  "https://api.github.com/repos/replicatedhq/kurl/dispatches"
```

# rook-ceph

```bash
image=addons/rook/1.0.4/build-images/rook-ceph
curl -H "Authorization: token $GH_PAT" \
  -H 'Accept: application/json' \
  -d "{\"event_type\": \"build-image\", \"client_payload\": {\"image\": \"${image}\"}}" \
  "https://api.github.com/repos/replicatedhq/kurl/dispatches"
```
