Building with Vagrant
=====================

Introduction
------------
To get started with BCPC locally, we strongly recommend using the Vagrant mechanism. Vagrant is a tool that allows for easy provisioning of development environments that can be downloaded from [https://www.vagrantup.com](https://www.vagrantup.com).

Prerequisites
-------------
* OS X or Linux
* Processor that supports VT-x virtualization extensions
* 16 GB of memory
* 100 GB of free disk space
* Vagrant 1.7 or better ([https://www.vagrantup.com](https://www.vagrantup.com))
* VirtualBox 4.3 or better ([https://www.virtualbox.org](https://www.virtualbox.org))
* Git
* curl
* rsync
* ssh

On OS X, installing [Xcode](https://itunes.apple.com/us/app/xcode/id497799835?mt=12) from the Mac App Store and then installing Xcode's command-line tools from within Xcode will provide Git. On Linux, please consult documentation for your particular distribution to install any missing prerequisites via `apt-get`, `yum`, or another distribution-specific package manager.

Doing the build
---------------
1. From the root of the chef-bcpc Git repository, change directory to `bootstrap/vagrant_scripts`.
2. If you need to use a proxy server to reach the Internet, copy `bootstrap/config/bootstrap_config.sh.template` to `bootstrap/config/bootstrap_config.sh`.
3. Uncomment the lines that export `BOOTSTRAP_HTTP_PROXY` and `BOOTSTRAP_HTTPS_PROXY`, adding the host:port for your proxy server.
4. If your HTTPS proxy performs man-in-the-middle rewriting of SSL connections, or you have some other need to augment the system root certificate stores of the VMs, additionally uncomment the line that exports `BOOTSTRAP_ADDITIONAL_CACERTS_DIR` and set this environment variable to a directory on your computer where the necessary CA certificates can be found in PEM-encoded X.509 files. (Obviously put the certificates in that directory as well.)
5. Tweak any other configuration values you might want to, but the defaults should be reasonable for most people.
6. Run `./BOOT_GO.sh`.
7. Watch the magic! (The build process usually takes 45-60 minutes to complete, depending on the speed of your computer and Internet connection.)

That was easy!
--------------
Hooray!

But what is it doing?
---------------------
Glad you asked! Of course you may read all the scripts within to see exactly what's happening, but here is a summary of the actions the build process takes.

1. `BOOT_GO.sh` loads a build configuration file if present (from `bootstrap/config/bootstrap_config.sh`), using default settings for anything not specified.
2. `BOOT_GO.sh` runs `bootstrap/common_scripts/bootstrap_validate_env.sh` and `bootstrap/vagrant_scripts/vagrant_test.sh`, which check a few things about your environment, mainly looking for Vagrant and certain programs that are needed to kick off the build process.
3. If you have configured HTTP/HTTPS proxy servers in the configuration file, `BOOT_GO.sh` runs `bootstrap/common_scripts/bootstrap_proxy_setup.sh`, which checks to see if these proxy servers work for accessing HTTP/HTTPS URLs (specifically, it tests against Google and GitHub respectively). **Note that this check occurs from your host OS rather than from within a VM.**
4. `BOOT_GO.sh` runs `bootstrap/common_scripts/bootstrap_prereqs.sh`, which downloads various files used by the bootstrap process (not all of them are used by the Vagrant method of bootstrapping, but this script is shared between the Vagrant and non-Vagrant bootstrap pathways). The script has a full and complete list of all files that are downloaded, and the total size of all downloaded files is around 1 GB.
5. `BOOT_GO.sh` runs `bootstrap/vagrant_scripts/vagrant_clean.sh`, which is effectively a wrapper for `vagrant destroy -f` (delete any existing BCPC VMs). If you have BCPC VMs around that were built using the older bootstrap process, this will **not** recognize them and you will need to delete them from VirtualBox manually (you will get an error message when Vagrant tries to launch the new cluster).
6. `BOOT_GO.sh` runs `bootstrap/vagrant_scripts/vagrant_create.sh`, which clears out existing VirtualBox DHCP server configurations and then calls `vagrant up`.
7. `vagrant up` reads the `Vagrantfile` and launches 4 VMs: one bootstrap node and 3 BCPC cluster nodes. `Vagrantfile` performs some additional environment validations and then launches each VM in turn, provisioning it with some inline shell scripts in the Vagrantfile, creating networks and assigning network addresses, and creating extra disks for the BCPC cluster nodes.
8. `BOOT_GO.sh` runs `bootstrap/vagrant_scripts/vagrant_configure_chef.sh`, which is where the meat of the cluster setup happens.
9. `vagrant_configure_chef.sh` installs Chef Server 12 on the bootstrap node and Chef Client 12 on all 4 nodes. On the bootstrap node, it configures credentials for the nodes to access Chef Server, executes `knife bootstrap` to link the nodes to the Chef Server installation (but does not immediately begin the provisioning process), and configures Chef client permissions so that the head node and bootstrap node can write items into a Chef data bag. It then copies the BCPC repository into the bootstrap VM via VirtualBox shared folders, executes `bootstrap/common_scripts/common_build_bins.sh` within the bootstrap VM to build various binary packages, uploads the `bcpc` cookbook and its dependencies to Chef Server, and selects the roles for each cluster node.
10. If `$BOOTSTRAP_CHEF_DO_CONVERGE` is set to `1` (the default), `vagrant_configure_chef.sh` will execute Chef on each node in turn to converge it with the BCPC recipes, and then execute Chef on the head node one more time so that the head node can update itself based on the roles assigned to the other two nodes.
11. If you allowed `vagrant_configure_chef.sh` to converge the cluster nodes, `BOOT_GO.sh` runs `bootstrap/vagrant_scripts/vagrant_print_useful_info.sh`, which prints out the URL of the BCPC landing page and some passwords to get you going.

Something didn't work!
----------------------
Oh no! Please let us know by creating a GitHub issue with as much information as possible: what operating system, any configuration changes you may have made, as much output from the build process as possible, etc.
