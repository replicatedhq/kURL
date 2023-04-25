# ADR 10: kURL new versioning scheme

## Context
Based on our prior experience, offering customers the ability to select various add-on versions provides them with significant flexibility, but it also creates numerous challenges. Presently, we're struggling to ensure that each customer's chosen add-ons are compatible with one another and that migration paths are available for all potential combinations. Moreover our user feedback indicates that stability and predictability are their top priorities, rather than the specific technologies they are running behind the scenes.

## Decision
Based on users feedback and the struggling we are facing to maintain kURL upgrades predictability, we have decided to adopt a more opinionated approach to delivering our Kubernetes distribution. This will involve implementing a well-designed versioning scheme, which is outlined in detail in this Architecture Decision Record.

## Solution
Under the new versioning scheme, our offering will be organised into Channels that correspond to specific Kubernetes minor versions. As of now, we will begin with a single channel named v1.27, which serves as our official offering for Kubernetes versions v1.27.x. Put simply, users who wish to install or keep their installations on Kubernetes v1.27 will remain on this Channel.

Consequently, we can initiate the design of our new kURL installation YAML in the following manner:

```yaml
apiVersion: "cluster.kurl.sh/v1"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.27”
```

With the Channel (Kubernetes) now established as the basis for our delivery model, we can enable users to select a Version within this channel, which will allow them to access a specific set of Kubernetes-related features and functionalities (add-ons) that have been thoroughly tested and vetted by our team. This Version serves to abstract each individual add-on version into our own standardised version, ensuring that users can reliably and confidently utilise our offering without worrying about compatibility or interoperability issues.

We will establish the practice of starting each Channel with a version v1.0.0 that groups together the initial set of add-ons (and respective versions) we support for that particular version. As a result, we will need to update the YAML file to reflect this approach, an initial Installer would look like this:

```yaml
apiVersion: "cluster.kurl.sh/v1"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.27"
  version:  "1.0.0"
```
While we will delve into the specifics of what the new kURL Version inside a Channel entails in more detail shortly, for the sake of simplicity, bear in mind that this Version essentially groups together a list of add-ons that are compatible with a given Kubernetes version. As such, users can easily upgrade to a newer version within the same Channel by updating the YAML version field and running the installer accordingly. For instance, the following example illustrates how to update the cluster to kURL version v1.8.0 within 1.27 Channel:

```yaml
apiVersion: "cluster.kurl.sh/v1"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.27"
  version:  "1.8.0"
```
As we've designed it, users are free to skip as many versions as they wish within a given Channel without any restrictions. This means that they can easily move between kURL versions within the same Channel at their own pace, depending on their individual needs and preferences, without any limitations or requirements.

_From now on this ADR may refer to Channel and Version in its short version "vChannel+kURL Version", for example v1.26+1.1.0 is the equivalent of Channel 1.26 and kURL version 1.1.0_

### About kURL version inside a Channel
As we've discussed earlier, a kURL Version within a given Channel comprises a list of add-ons, each with their own specific version. With that in mind, we could begin by outlining the initial group of add-ons that would make up kURL Version 1.0.0 within a given Channel 1.26. This version could includes the following set of add-ons, each with their corresponding version (this set of add-ons mentioned is used solely as an example and is not the definitive list of add-ons):

| Add-on | Version |
|----------|-------|
|Kubernetes| v1.26.0|
|Containerd| v1.6.0 |
|Flannel | v0.21.4|
|Contour | v1.24.3 |
|Minio | 2023-04-13T03-08-07Z |
|OpenEBS | v3.4.0 |
|Rook | v1.11.0 |

To simplify things this entire list of add-on names and versions would be consolidated into a single kURL Version: "1.0.0".  Similarly, within Channel 1.26, we can define another kURL Version, such as "1.1.0", which would be composed of the same set of add-ons but with different and more up-to-date versions. Here is an example list of the add-ons versions that could be included in such version.

| Add-on | Version |
|----------|-------|
|Kubernetes| v1.26.1|
|Containerd| v1.6.3 |
|Flannel | v0.21.4|
|Contour | v1.24.3 |
|Minio | 2023-04-13T03-08-07Z |
|OpenEBS | v3.5.0 |
|Rook | v1.11.3 |

It's important to note that the Kubernetes minor version remains unchanged within the same Channel. Any upgrades to add-on versions must be compatible with their first kURL version in the Channel (like for example: upgrading from OpenEBS 3.4.0 to 3.5.0 can be achieved without data migration). This may sometimes involve _minor_ version upgrades, but in most cases, only _patch_ version upgrades will be allowed within a Channel.

### Upgrades between Channels

Upgrades between different Channels can possibly involve longer cluster downtime due to data migration. This may become very complex as some add-ons may not be supported in updated Kubernetes versions. Therefore, it's crucial for us to keep track of the current state of the cluster before staring the upgrade.

To manage upgrades between Channels, we have decided to allow only one Channel version upgrade at a time. This means that customers can upgrade from Channel 1.25 to 1.26, but upgrades from 1.25 to 1.27 would be blocked. Additionally, users must be in the **latest** version within one Channel before upgrading to any version in the next Channel. By requiring users to be in the latest Channel version before upgrading to the next one, we can ensure two things: Firstly, we have a clear understanding of the current state of the cluster, which is essential for successful upgrades. Secondly, it provides us with some flexibility in preparing the cluster for the Channel upgrade, as we can introduce a new version in the previous Channel to gradually prepare the cluster to the next Channel.

To help us better comprehend the restrictions and limitations involved in upgrading between Channels, let us consider a hypothetical scenario. This will provide us with a practical example to illustrate the concept and highlight the challenges that may arise during the upgrading process.

| Channel | Version|
|---------|--------|
| 1.25    | 1.0.0  |
| 1.25    | 1.1.0  |
| 1.25    | 1.2.0  |
| 1.26    | 1.0.0  |
| 1.26    | 1.1.0  |
| 1.26    | 1.2.0  |
| 1.27    | 1.0.0  |

Based on the above-mentioned scenarios, the following table outlines various upgrade attempts and their respective outcomes:

| From       | To        | Outcome |
|------------|-----------|---------|
|v1.25+1.0.0.|v1.25+1.2.0|Success. Upgrades inside the same Channel are allowed. |
|v1.25+1.0.0.|v1.26+1.0.0|Failure. Users can only upgrade to the next Channel when they are already running the latest version of the current Channel. |
|v1.25+1.2.0.|v1.26+1.2.0|Success. Upgrades from the latest version of the current Channel to any version on the next Channel are allowed. |
|v1.25+1.2.0.|v1.27+1.0.0|Failure. Upgrades skipping a Channel are not allowed. |

_Downgrades are strictly prohibited under any circumstances. Once a cluster is upgraded to a newer version in a specific Channel, there is no going back to a previous version. This is to maintain consistency and avoid any potential issues that may arise from incompatible configurations or data._

### Additional Details

#### Allowing for some degree of customisation
Our aim is to maintain a level of opinionated approach towards the technology we offer, while also allowing a certain level of customisation for our customers. We believe that the customers should have the freedom to decide what they want to install on their clusters, and this includes factors such as having or not having an object storage API for example. In order to facilitate this, we plan to abstract such complex concepts into simpler and easier-to-understand terms.

Let's exemplify: to make an Object Storage API available inside the cluster, customers can choose to install the "Minio" add-on. The details about which tool provides the Object Storage API inside kURL are not crucial for the users. What matters to them is having an ObjectStorageAPI available on their cluster. With this in mind, users can easily achieve their desired installation by using the following Installer:

```yaml
apiVersion: "cluster.kurl.sh/v1"
kind: "Installer"
metadata:
  name: "cluster"
spec:
  channel:  "1.27"
  version:  "1.8.0"
  objectStorage:
    enabled: true
    credentialsSecrets:
    - namespace: "default"
      name: "object-storage"
```
Expanding on the previous statement, the reason why the configuration would deploy Minio in the cluster is because it has been selected as the official Object Storage API provider for kURL. The `credentialsSecrets` property allows the user to specify where they expect to see the credentials required to access this Object Storage API. However, it is important to note that this is only an example and each individual configuration and selected add-ons will require further discussion and customisation.
  

## Status

Proposed

## Consequences

1. In order to plan the migration path from the current kURL version to the new one, we must determine the necessary versions that the customer must be running to transition to the first version in the initial channel.
2. The vendor portal will need to be modified to accommodate this new arrangement.
3. An API must be designed and developed in order to provide information about the current Channels and Versions available.
4. All non-essential add-ons would need to be manually enabled by the user. Non-essential add-ons being anything other than Kubernetes, CNI and CSI.
5. Not all knobs in all add-ons will be available for the customer to tweak.
6. We will have more control on what is supported by the cluster, this hugely simplifies the infrastructure and allow us for better testing and stability.
7. Users may be forced to to execute multiple step upgrades (_current version_ > _latest version in the Channel_ > _new Channel_), we might want to automate this.
8. kurl.sh will need to be redesigned/reimplemented.
9. _Testgrid_ will need to be reimplemented or replaced by something else.
