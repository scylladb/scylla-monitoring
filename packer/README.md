# Scylla Monitor Image

## Requirements
- Packer >= v1.10.0
- Packer AWS and GCP plugins

To install the required plugins, run the following:

```shell
packer plugins install github.com/hashicorp/googlecompute
packer plugins install github.com/hashicorp/amazon
```

## Build
To build the Scylla Monitor Image, make sure you have [Authentication](#authentication) set up, and run the following command from the `siren-devops/cluster/monitor` directory:

```shell
packer build -var monitor_version="4.6.1" scylla-monitor-template.json
```
You can build a specific cloud only by using the `-only` flag. for example:
```shell
# AWS only
packer build -only=amazon-ebs -var monitor_version="4.6.1" scylla-monitor-template.json

# GCP only
packer build -only=googlecompute -var monitor_version="4.6.1" scylla-monitor-template.json
```
## Variables

The Scylla Monitor Image uses default variables that are declared in the packer template file, for example `aws_source_ami`, `gcp_project_id` etc.
You can override these default variables by creating a `variables.json` with the desired variable values, for example:

```json
{
  "monitor_version": "4.6.1",
  "aws_subnet_id": "your_aws_subnet_id",
  "gcp_project_id": "your_gcp_project_id",
  "gcp_zone": "your_gcp_zone"
}
```
And when running the packer build command, include the `-var-file` option to specify the `variables.json` file:

```shell
packer build -var-file=variables.json scylla-monitor-template.json
```

### Architecture

By default the image is built for `amd64`. To build an ARM image (AWS and GCP), pass `-var arch=arm64`.
On GCP, arm64 uses a C4A machine with a hyperdisk and is published to the `scylladb-monitor-arm64` image family:

```shell
packer build -var monitor_version="4.6.1" -var arch=arm64 scylla-monitor-template.json
```

### AWS AMI regions

By default the AMI is copied to all production regions: `us-west-2,us-east-2,eu-west-2,eu-west-1,eu-central-1,eu-north-1,eu-west-3,ca-central-1`.
To limit the copy to a specific region or set of regions (useful for testing), override `aws_ami_regions`:

```shell
# Single region
packer build -var monitor_version="4.6.1" -var aws_ami_regions=us-east-1 scylla-monitor-template.json

# Multiple specific regions
packer build -var monitor_version="4.6.1" -var aws_ami_regions=us-east-1,eu-west-1 scylla-monitor-template.json
```


### Test builds in CI

The **Build Cloud Images** workflow can be run manually with the CI credentials.
Push the branch to the main repository and run the workflow from it. Optional inputs:

- `arch`: `all`, `amd64` or `arm64`.
- `cloud`: `all`, `aws` or `gce`.
- `gcp_zone`: GCE build zone.
- `aws_ami_regions`: regions to copy the AMI to, e.g. `us-east-1`.
- `name_tag`: replaces the version in the image name, e.g. `4.17.0-rc1-test` gives
  `scylladb-monitor-4-17-0-rc1-test-arm64-<time>`. The version labels keep `monitor_version`.
- `ref`: git ref to check out for `packer/`, e.g. the branch under test (default: the `monitor_version` tag).
- `test`: the AMI is not made public and the GCE image is not added to an image family.

Remove test images with `delete_cloud_images.sh` (or the **Delete Cloud Images** workflow)
using the name prefix, e.g. `--name 'scylladb-monitor-4-17-0-rc1-test*'`.

## Authentication

### AWS
Ensure `aws_access_key_id` and `aws_secret_access_key` are configured either in a local credentials file (ex. `~/.aws/credentials`) or as environment variables.

#### GCP
Set your GCP service account key as an environment variable:
```shell
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your/service-account-file.json"
```

## Deleting images

`delete_cloud_images.sh` removes images by their packer name (`monitor_image_name`) from
AWS (the AMI and its snapshot, in `aws_region` and every region in `aws_ami_regions`)
and from GCP (`gcp_project_id`). It is a dry run unless `--delete` is given:

```shell
# show what would be removed
./delete_cloud_images.sh --name scylladb-monitor-4-16-0-rc0-2026-06-28t11-42-58z

# a trailing * matches several builds; restrict to one cloud with --cloud aws|gcp
./delete_cloud_images.sh --name 'scylladb-monitor-4-16-0-rc*' --cloud aws

# actually delete
./delete_cloud_images.sh --name scylladb-monitor-4-16-0-rc0-2026-06-28t11-42-58z --delete
```

Only AMIs owned by the current AWS account are considered, so run it with the
credentials of the account that built the images. The same script is exposed as the
manual **Delete Cloud Images** GitHub Actions workflow, which uses the CI account
credentials; pick `action: dry-run` first to review the list, then re-run with `delete`.
