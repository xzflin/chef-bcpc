Ansible hardware build guide
===
This process is designed to simulate an actual hardware build-out as closely as possible. To that end, it sacrifices speed and convenience for correctness. There are a number of manual steps, and there are some steps that are not necessary on actual hardware builds in order to trick certain parts of the software stack (mostly having to do with the networking layout). Where present, these steps will be indicated.

You **must** have a complete local copy of all packages repositories, a complete copy of the BCPC local build cache (by default in `$HOME/.bcpc-cache`), and all necessary packages from PyPI to get Ansible installed and running on the bastion host.

Minimum Prerequisites
---------------------
* an OS X or Linux bastion host
* Ansible 1.9.4 or better on the bastion host
* Git, curl, rsync, ssh

cluster.yml/cluster.txt preparation
---
* Using the `ansible-cluster.yml.example` file as a reference, create your `cluster.yml` file.
* The hardware type given for each node is interpolated into the string `BCPC-Hardware-[hardware_type]` when selecting a role file for the node that informs Chef of the hardware layout of the node (e.g., what the network interfaces are named). This is necessary for deploying multiple hardware types within a single cluster.
* Using `bootstrap/ansible_scripts/scripts/cluster_yaml_to_inventory.py`, generate the Ansible inventory file for the cluster.
* Using `bootstrap/ansible_scripts/scripts/cluster_manifest_converter.py`, down-convert the YAML file to `cluster.txt` (for use by legacy scripts).
* Place `cluster.yml`, `cluster.txt`, `environments/CLUSTERNAME.json`, and your `roles/*.json` into the **chef-bcpc-prop** repository under a branch named after your cluster. These files will be overlayed on top of the **chef-bcpc** repository during deployment.

Repository preparation
---
* Prepare release tags for all versions of all repositories you intend to deploy, corresponding to the version numbers you will be setting in the Ansible group variables.
* The name and version of the repository from the group variables are concatenated together to locate the ZIP file and the directory within. In order to have a ZIP file with the expected layout, you must download a ZIP file of the tag/branch corresponding to the name of the version.
* **FOR EXAMPLE**: if you specify that **chef-bcpc** has a deployed version of **5.8.0**, you should make a **5.8.0** tag on the repository and download the ZIP file from that, because the ZIP file will be named `chef-bcpc-5.8.0.zip` and when decompressed the contents of the repository will be under the `chef-bcpc-5.8.0` directory.
* You can manually construct the ZIP files if needed with the above information as long as the layout is correct.
* Git metadata is not used by the playbooks, only the working copy, so it does not matter whether you include `.git`.
* Prepare **chef-bcpc-prop** and any add-on cookbooks in the same way.

Ansible preparation
---
* Create a staging location on your bastion host (e.g., `$HOME/bcpc-deployment`). This directory is useful for storing various files used by the build process, as well as a virtualenv for Ansible.
* Copy `bootstrap/ansible_scripts/group_vars/vars.template` to `CLUSTERNAME` within that same directory, where `CLUSTERNAME` is the name of your cluster. This file will be referred to as the **group variables** file.
* Create a `git-staging` directory underneath this directory. Set the value of `controlnode_git_staging_dir` in the group variables to this value.
* `git-staging` is expected to contain ZIP files of the different repositories specified in the group variables. The easiest way to obtain these is via GitHub's **Download ZIP** button. See the above sections for information on preparing them.
* Create a `bootstrap-files` directory underneath this directory. Set the value of `controlnode_files_dir` in the group variables to this value.
* Copy the contents of your BCPC bootstrap cache (by default, `$HOME/.bcpc-cache`) to `bootstrap-files/VERSIONNAME` on the bastion host, where **VERSIONNAME** is the version of **chef-bcpc** being deployed. Symlinks will **not** work.
* If you do not have a local BCPC cache, run `BOOTSTRAP_CACHE_DIR=$HOME/.bcpc-cache REPO_ROOT=$(git rev-parse --show-toplevel) bootstrap/shared/shared_prereqs.sh` from the root of the repository to populate the cache.
* If you are electing to deploy prebuilt binaries instead of allowing the bootstrap node to build them itself, set `use_prebuilt_binaries` to true in the group variables, create `bootstrap-files/VERSIONNAME-prebuilt`, and copy the contents of `cookbooks/bcpc/files/default/bins` into this directory.
* Locate the root of the apt mirror on the bastion host. Set the value of `controlnode_apt_mirror_dir` in the group variables to this value.
* Generate an SSH key pair in your staging directory with `ssh-keygen -f CLUSTERNAME`. Set the value of `ansible_ssh_private_key_file` in the group variables to the path to the private key. Set the value of `operations_key` to the public key itself (copy and paste it in there, don't provide the path). **Save this somewhere secure, because if you lose it, you're in trouble.**
* Review the group variables for any additional settings you may wish to or need to change.
* Install **virtualenv** via `pip install virtualenv` or operating system packages so that you may install Ansible and its support packages without interfering with system Python.
* Create a virtualenv in the staging directory with `virtualenv path/to/staging-dir` (if you are in the directory, `virtualenv .` will suffice). The virtualenv must be using Python 2.x (2.7 recommended) and not Python 3.x because of Ansible restrictions, so if the virtualenv is set up with the wrong Python interpreter, please recreate it with the `-p` setting.
* Activate the virtualenv from within the staging directory with `source bin/activate`.
* Install packages into the virtualenv corresponding to the `requirements.txt` below. Usually the easiest way is to transfer wheels or tarballs from PyPI to the bastion host and then manually install them with `pip install`.
```
Jinja2==2.8
MarkupSafe==0.23
PyYAML==3.11
ansible==1.9.4
argparse==1.2.1
paramiko==1.16.0
pycrypto==2.6.1
wsgiref==0.1.2
```

Bootstrap host preparation
---
* Download an Ubuntu server ISO from [http://www.ubuntu.com/download/server] to boot the bootstrap node from.
* Configure a node to act as the bootstrap node with three block devices:
  * `sda` is the root volume
  * `sdb` is mounted at `/mnt` (scratch space)
  * `sdc` is mounted at `/bcpc` (contains everything used by the bootstrap process)
* Manually install Ubuntu 14.04 LTS on the bootstrap node using your preferred mechanism (LOM virtual media, USB key, disc, etc.).
* It is recommended that you create a user named **ubuntu** during setup, as this user will be needed to create the **operations** user and will then be disabled by `tasks-create-bootstrap-users.yml`.

The rest
---
Have a look at **ansible_cluster_convergence.md** for information on converging nodes and getting the full cluster up and running.
