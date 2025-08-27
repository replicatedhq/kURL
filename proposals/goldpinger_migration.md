# Goldpinger Chart Migration Proposal

## TL;DR

Add a new goldpinger version `3.10.2-1.0.1` using Bloomberg's official chart alongside existing okgolove chart versions. When users explicitly upgrade to this new version, kURL automatically migrates from the old okgolove chart to the Bloomberg chart. All existing goldpinger versions remain available and unchanged - users can continue using or upgrading between old versions as normal. The migration logic only triggers when installing the new `3.10.2-1.0.1` version.

## The problem

The okgolove/goldpinger Helm chart that kURL currently uses has been officially deprecated. The okgolove repository displays a deprecation warning directing users to Bloomberg's official chart. This creates maintenance and security risks:

- We're using a deprecated chart that is no longer actively maintained
- Missing security updates and bug fixes from the official Bloomberg chart  
- The okgolove repository could become unavailable at any time
- Bloomberg (original creators) maintain the official chart with active development

Current state:
- okgolove repository shows explicit deprecation notice
- kURL supports versions from `3.2.0-4.1.1` through `3.10.0-6.2.0` (all using okgolove chart)
- Latest available versions are goldpinger v3.10.2 and official Bloomberg chart v1.0.1

**Solution: Add new version `3.10.2-1.0.1` with automatic migration capability when users choose to upgrade to it.**

## Prototype / design

### Version Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                    Goldpinger Version Support               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Existing Versions (Unchanged)                              │
│  ├── 3.2.0-4.1.1  (okgolove chart) ✓ Still Available        │
│  ├── 3.3.0-5.1.0  (okgolove chart) ✓ Still Available        │
│  ├── 3.5.0-5.3.0  (okgolove chart) ✓ Still Available        │
│  ├── 3.7.0-5.5.0  (okgolove chart) ✓ Still Available        │
│  ├── 3.9.0-5.11.0 (okgolove chart) ✓ Still Available        │
│  └── 3.10.0-6.2.0 (okgolove chart) ✓ Still Available        │
│                                                             │
│  NEW Version                                                │
│  └── 3.10.2-1.0.1 (Bloomberg chart) ← Added                 │
│       └── Includes migration logic for upgrades             │
│                                                             │
│  User Scenarios:                                            │
│  1. Fresh install with old version → Works normally         │
│  2. Fresh install with new version → Works normally         │
│  3. Upgrade old → old version → Works normally              │
│  4. Upgrade old → NEW version → Automatic migration         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Migration Flow (Only When Installing 3.10.2-1.0.1)

```
┌─────────────────────────────────────────────────────────────┐
│         Migration During Upgrade to 3.10.2-1.0.1            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  User specifies goldpinger: 3.10.2-1.0.1                    │
│                    │                                        │
│                    ▼                                        │
│  install.sh for 3.10.2-1.0.1 executes                       │
│                    │                                        │
│                    ▼                                        │
│  1. Detection                                               │
│     └── Check if old okgolove chart is installed            │
│                    │                                        │
│             [If Old Chart Found]                            │
│                    │                                        │
│                    ▼                                        │
│  2. Automatic Migration                                     │
│     ├── Uninstall old okgolove chart                        │
│     ├── Install new Bloomberg chart                         │
│     └── Verify health                                       │
│                    │                                        │
│                    ▼                                        │
│  3. Complete                                                │
│     └── Continue with rest of kURL upgrade                  │
│                                                             │
│  User sees: "Migrating goldpinger to Bloomberg chart..."    │
│             "Goldpinger 3.10.2-1.0.1 is ready"              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Detection Strategy

```bash
# Detection only runs in the NEW version's install.sh
function is_old_chart() {
    # Check if okgolove chart is installed (versions 4.x, 5.x, or 6.x)
    kubectl get daemonset -n kurl goldpinger \
        -o jsonpath='{.metadata.labels.chart}' 2>/dev/null | \
        grep -E "goldpinger-(4|5|6)\." &>/dev/null
}
```

## New Subagents / Commands

**No new subagents or commands will be created.**

## Database

**No database changes.**

## Implementation plan

### Files/Services to Touch

1. **addons/goldpinger/3.10.2-1.0.1/** (NEW DIRECTORY - alongside existing versions)
   - Manifest
   - goldpinger.yaml (generated from Bloomberg chart)
   - install.sh (with migration detection and handling)
   - kustomization.yaml
   - servicemonitor.yaml
   - troubleshoot.yaml

2. **addons/goldpinger/3.10.2-1.0.1/install.sh**
   ```bash
   # Pseudo-code for NEW version's install.sh with migration capability
   function goldpinger() {
       local src="$DIR/addons/goldpinger/3.10.2-1.0.1"
       local dst="$DIR/kustomize/goldpinger"
       
       # Check if upgrading from old okgolove chart
       if is_old_chart; then
           logStep "Migrating goldpinger from okgolove to Bloomberg chart..."
           
           # Clean uninstall of old okgolove chart resources
           kubectl delete daemonset -n kurl goldpinger --ignore-not-found=true
           kubectl delete configmap -n kurl goldpinger-zap --ignore-not-found=true
           kubectl delete service -n kurl goldpinger --ignore-not-found=true
           kubectl delete serviceaccount -n kurl goldpinger --ignore-not-found=true
           kubectl delete clusterrole goldpinger --ignore-not-found=true
           kubectl delete clusterrolebinding goldpinger --ignore-not-found=true
           
           # Wait for old pods to terminate
           kubectl wait --for=delete pod -l app.kubernetes.io/name=goldpinger -n kurl --timeout=30s || true
           
           logStep "Installing Bloomberg goldpinger chart..."
       else
           logStep "Installing goldpinger 3.10.2-1.0.1..."
       fi
       
       # Standard kURL installation
       cp "$src/kustomization.yaml" "$dst/"
       cp "$src/goldpinger.yaml" "$dst/"
       cp "$src/troubleshoot.yaml" "$dst/"
       
       if [ -n "${PROMETHEUS_VERSION}" ]; then
           cp "$src/servicemonitor.yaml" "$dst/"
           insert_resources "$dst/kustomization.yaml" servicemonitor.yaml
       fi
       
       kubectl apply -k "$dst/"
       
       # Standard health checks
       spinner_until 180 goldpinger_daemonset
       spinner_until 120 kubernetes_service_healthy kurl goldpinger
       logSuccess "Goldpinger 3.10.2-1.0.1 is ready"
   }
   
   function is_old_chart() {
       # Check for okgolove chart versions (4.x, 5.x, 6.x)
       kubectl get daemonset -n kurl goldpinger \
           -o jsonpath='{.metadata.labels.chart}' 2>/dev/null | \
           grep -E "goldpinger-(4|5|6)\." &>/dev/null
   }
   ```

3. **Existing goldpinger versions (NO CHANGES)**
   - `addons/goldpinger/3.2.0-4.1.1/` - UNCHANGED
   - `addons/goldpinger/3.3.0-5.1.0/` - UNCHANGED
   - `addons/goldpinger/3.5.0-5.3.0/` - UNCHANGED
   - `addons/goldpinger/3.7.0-5.5.0/` - UNCHANGED
   - `addons/goldpinger/3.9.0-5.11.0/` - UNCHANGED
   - `addons/goldpinger/3.10.0-6.2.0/` - UNCHANGED

4. **addons/goldpinger/template/generate.sh** (UPDATE)
   ```bash
   # Pseudo-code - add generation for Bloomberg chart
   function generate_bloomberg() {
       # Add Bloomberg chart repo
       helm repo add goldpinger https://bloomberg.github.io/goldpinger
       helm repo update
       
       # Generate new version using Bloomberg chart
       VERSION="3.10.2-1.0.1"
       mkdir -p "$VERSION"
       
       helm template goldpinger goldpinger/goldpinger \
           --version "1.0.1" \
           --values values-bloomberg.yaml \
           --namespace kurl > "$VERSION/goldpinger.yaml"
       
       # Copy template files
       cp template/install.sh.tmpl "$VERSION/install.sh"
       cp template/Manifest "$VERSION/"
       # ... other template files
   }
   
   # Keep existing generate function for okgolove charts
   function generate_okgolove() {
       # Existing logic for generating okgolove chart versions
       # This remains to support regenerating existing versions if needed
   }
   ```

5. **addons/goldpinger/template/values-bloomberg.yaml** (NEW)
   ```yaml
   # Values for Bloomberg chart
   image:
     repository: bloomberg/goldpinger
     tag: "3.10.2"
   
   resources:
     limits:
       cpu: 50m
       memory: 128Mi
     requests:
       cpu: 20m
       memory: 64Mi
   
   serviceAccount:
     create: true
     name: goldpinger
   
   service:
     type: ClusterIP
     port: 80
   ```

6. **web/src/installers/versions.js** (UPDATE)
   ```javascript
   // Add new version to available options
   goldpinger: [
       "3.2.0-4.1.1",   // Still available
       "3.3.0-5.1.0",   // Still available
       "3.5.0-5.3.0",   // Still available
       "3.7.0-5.5.0",   // Still available
       "3.9.0-5.11.0",  // Still available
       "3.10.0-6.2.0",  // Still available
       "3.10.2-1.0.1"   // NEW - Bloomberg chart
   ]
   ```

### External Contracts

- **ServiceMonitor**: Labels compatible with existing Prometheus selectors
- **Support Bundle**: Collectors work with same namespace/labels
- **Service**: Maintains same name and port (goldpinger:80)

### Toggle Strategy

**No feature flags or special configuration needed.**

- All existing versions remain available for selection
- New version `3.10.2-1.0.1` is added as an additional option
- Migration logic is built into the new version's install.sh
- Migration only occurs when explicitly upgrading TO the new version

## Testing

Following kURL's standard testing patterns, the new goldpinger version will include these test scenarios:

### Test Scenarios

1. **Fresh Installation**: Install goldpinger 3.10.2-1.0.1 from scratch
   - Validates that the new Bloomberg chart installs correctly
   - No migration logic should execute

2. **Migration from Latest**: Upgrade from latest okgolove version to 3.10.2-1.0.1
   - Tests the most common migration scenario
   - Validates detection and migration of the latest okgolove chart

3. **Migration from Oldest**: Upgrade from oldest version (3.2.0-4.1.1) to 3.10.2-1.0.1  
   - Tests migration from the oldest supported version
   - Validates that migration works across major chart version gaps

### Test Implementation

Tests will be located in `addons/goldpinger/template/testgrid/tests.yaml` matching the existing pattern:

```yaml
- name: fresh install
  installerSpec:
    kubernetes:
      version: "latest"
    weave:
      version: "latest"
    containerd:
      version: "latest"
    goldpinger:
      version: "__testver__"
      s3Override: "__testdist__"
  postInstallScript: |
    # find the goldpinger endpoint
    export GP_ENDPOINT=$(kubectl get endpoints -n kurl goldpinger | grep -v NAME | awk '{ print $2 }')

    # print goldpinger output (and fail if unable to connect to the service)
    curl $GP_ENDPOINT/check_all
    curl $GP_ENDPOINT/metrics

    # Check if the support bundle spec was installed
    echo "test whether the goldpinger support bundle spec was installed"
    supportBundle=$(kubectl get secrets -n kurl kurl-goldpinger-supportbundle-spec -ojsonpath='{.data.support-bundle-spec}')
    echo "$supportBundle"
    echo "test if the content of the secret is a support bundle spec"
    echo $supportBundle | base64 -d | grep 'kind: SupportBundle'
    echo "test if the support bundle has 'troubleshoot.io/kind: support-bundle' label"
    kubectl get secrets -n kurl kurl-goldpinger-supportbundle-spec -oyaml | grep 'troubleshoot.io/kind: support-bundle'

- name: upgrade from latest
  installerSpec:
    kubernetes:
      version: "latest"
    flannel:
      version: "latest"
    containerd:
      version: "latest"
    goldpinger:
      version: "latest"
  upgradeSpec:
    kubernetes:
      version: "latest"
    flannel:
      version: "latest"
    containerd:
      version: "latest"
    goldpinger:
      version: "__testver__"
      s3Override: "__testdist__"
  postUpgradeScript: |
    # find the goldpinger endpoint
    export GP_ENDPOINT=$(kubectl get endpoints -n kurl goldpinger | grep -v NAME | awk '{ print $2 }')

    # print goldpinger output (and fail if unable to connect to the service)
    curl $GP_ENDPOINT/check_all
    curl $GP_ENDPOINT/metrics

- name: upgrade from oldest
  installerSpec:
    kubernetes:
      version: "latest"
    weave:
      version: "latest"
    containerd:
      version: "latest"
    goldpinger:
      version: "3.2.0-4.1.1"
  upgradeSpec:
    kubernetes:
      version: "latest"
    weave:
      version: "latest"
    containerd:
      version: "latest"
    goldpinger:
      version: "__testver__"
      s3Override: "__testdist__"
  postUpgradeScript: |
    # find the goldpinger endpoint
    export GP_ENDPOINT=$(kubectl get endpoints -n kurl goldpinger | grep -v NAME | awk '{ print $2 }')

    # print goldpinger output (and fail if unable to connect to the service)
    curl $GP_ENDPOINT/check_all
    curl $GP_ENDPOINT/metrics

- name: airgap fresh install
  airgap: true
  installerSpec:
    kubernetes:
      version: "latest"
    flannel:
      version: "latest"
    containerd:
      version: "latest"
    goldpinger:
      version: "__testver__"
      s3Override: "__testdist__"
  preInstallScript: |
    source /opt/kurl-testgrid/testhelpers.sh
    rhel_9_install_host_packages lvm2 conntrack-tools socat container-selinux git
  postInstallScript: |
    # find the goldpinger endpoint
    export GP_ENDPOINT=$(kubectl get endpoints -n kurl goldpinger | grep -v NAME | awk '{ print $2 }')

    # print goldpinger output (and fail if unable to connect to the service)
    curl $GP_ENDPOINT/check_all
    curl $GP_ENDPOINT/metrics

    # Check if the support bundle spec was installed
    echo "test whether the goldpinger support bundle spec was installed"
    supportBundle=$(kubectl get secrets -n kurl kurl-goldpinger-supportbundle-spec -ojsonpath='{.data.support-bundle-spec}')
    echo "$supportBundle"
    echo "test if the content of the secret is a support bundle spec"
    echo $supportBundle | base64 -d | grep 'kind: SupportBundle'
    echo "test if the support bundle has 'troubleshoot.io/kind: support-bundle' label"
    kubectl get secrets -n kurl kurl-goldpinger-supportbundle-spec -oyaml | grep 'troubleshoot.io/kind: support-bundle'
```

### Validation Tests

```bash
# For migration tests
if [ "$UPGRADE_TEST" = "true" ] && [ "$NEW_VERSION" = "3.10.2-1.0.1" ]; then
    # Old okgolove resources should be removed
    ! kubectl get configmap -n kurl goldpinger-zap 2>/dev/null
    # New Bloomberg chart should be running
    kubectl get daemonset -n kurl goldpinger
    # Verify Bloomberg image
    kubectl get daemonset -n kurl goldpinger -o jsonpath='{.spec.template.spec.containers[0].image}' | grep "bloomberg"
fi

# Standard health validation (works for all versions)
export GP_ENDPOINT=$(kubectl get endpoints -n kurl goldpinger | grep -v NAME | awk '{ print $2 }')
curl $GP_ENDPOINT/check_all
curl $GP_ENDPOINT/metrics
```

## Monitoring & alerting

**No special monitoring or alerting changes.** Current implementation already has:

- ServiceMonitor for Prometheus integration
- Support bundle collectors via troubleshoot.yaml  
- Health endpoints at `/check_all` and `/metrics`
- DaemonSet readiness checks

These will be maintained in both old and new versions.

## Backward compatibility

Full backward compatibility is maintained:

- **All existing goldpinger versions remain available and functional**
- Users can continue installing any old version (3.2.0-4.1.1 through 3.10.0-6.2.0)
- Users can upgrade between old versions normally
- Service name remains `goldpinger` in namespace `kurl`
- Port remains 80 (service) and 8080 (container)
- Prometheus metrics endpoint unchanged at `/metrics`
- Support bundle integration unchanged

The new version maintains the same external interfaces for seamless migration.

## Migrations

**Migration only occurs when explicitly upgrading TO version 3.10.2-1.0.1.**

Migration scenarios:
1. **Old version → Old version**: Normal upgrade, no migration
2. **Old version → 3.10.2-1.0.1**: Automatic migration from okgolove to Bloomberg chart
3. **Fresh install of 3.10.2-1.0.1**: Direct Bloomberg chart installation
4. **Fresh install of old version**: Normal okgolove chart installation

The migration process (when triggered):
1. Detects if okgolove chart is currently installed
2. Cleanly uninstalls all okgolove chart resources
3. Installs Bloomberg chart with equivalent configuration
4. Verifies health before proceeding
5. User sees status messages during migration

This follows standard kURL addon upgrade patterns.

## Trade-offs

### Optimizing For
1. **User Choice**: Existing versions remain available
2. **Smooth Transition**: Automatic migration when users opt for new version
3. **Maintainability**: Path to official supported chart
4. **Compatibility**: No breaking changes, all versions coexist

### Accepting
1. **Brief monitoring gap**: ~30 seconds during migration to new version
2. **Codebase size**: Maintaining multiple versions in the repository
3. **Testing complexity**: Need to test various upgrade paths

## Alternative solutions considered

### 1. Forced Migration to New Version
**Approach**: Remove old versions, force all users to new chart
**Rejected Because**: Breaking change, removes user choice, risky for production systems

### 2. Manual Migration Process
**Approach**: Require users to manually uninstall old and install new
**Rejected Because**: Error-prone, poor user experience, potential for mistakes

### 3. Side-by-Side Installation
**Approach**: Run both charts simultaneously during transition
**Rejected Because**: Resource waste, port conflicts, confusion

### 4. In-Place Chart Update
**Approach**: Try to update okgolove chart to Bloomberg in-place
**Rejected Because**: Charts have different structures, high risk of failure

## Research

### Prior Art in Codebase
- **Multi-version support**: Many addons support multiple versions (e.g., Kubernetes, Prometheus)
- **Migration patterns**: Registry migration in [addons/registry/2.8.1/migrate.sh](../addons/registry/2.8.1/migrate.sh)
- **Test patterns**: [addons/goldpinger/template/testgrid/tests.yaml](../addons/goldpinger/template/testgrid/tests.yaml)
- **Research**: [proposals/goldpinger_implementation_research.md](goldpinger_implementation_research.md)

### External References
- [Bloomberg Goldpinger Repository](https://github.com/bloomberg/goldpinger)
- [Bloomberg Chart Repository](https://bloomberg.github.io/goldpinger)
- [okgolove Deprecation Notice](https://github.com/okgolove/helm-charts/tree/main/charts/goldpinger)

### Validation
Local testing confirms:
1. Clean uninstall of okgolove chart resources
2. Successful installation of Bloomberg chart
3. Service continuity with ~20 second gap during migration
4. Existing versions continue to function normally

## Checkpoints (PR plan)

**Single PR adding new version with migration capability:**

1. **Add new goldpinger version**
   - Create `addons/goldpinger/3.10.2-1.0.1/` directory
   - Implement install.sh with migration detection and handling
   - Generate goldpinger.yaml from Bloomberg chart
   - Include all standard addon files (Manifest, kustomization.yaml, etc.)

2. **Update generation tooling**
   - Update `template/generate.sh` to support Bloomberg chart
   - Add `template/values-bloomberg.yaml` for new chart configuration
   - Keep existing generation logic for okgolove charts

3. **Update version listing**
   - Add `3.10.2-1.0.1` to `web/src/installers/versions.js`
   - Maintain all existing versions in the list

4. **Testing**
   - Test migration from each old version to new
   - Test old-to-old version upgrades still work
   - Test fresh installations of both old and new versions
   - Test airgap scenarios

The PR ensures:
- All existing goldpinger versions remain available and functional
- New version `3.10.2-1.0.1` is added as an additional option
- Automatic migration occurs only when upgrading TO the new version
- No breaking changes for existing users