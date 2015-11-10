Getting started
===

There are three different build paths available:
* local build using Vagrant
* local build using Ansible
* physical build using Ansible

Local build using Vagrant
---
The Vagrant build mechanism is most useful for proving out and testing changes related to the Chef recipes. It intentionally makes a number of changes that cause it to not act like a real hardware cluster, primarily relating to the role of the bootstrap node, but in turn these changes enable relatively quick cluster stand-up (under an hour in most cases, depending on external mirror speed; local mirrors can cut build time to around 30 minutes). Please see **vagrant_build_guide.md** for additional information on this build path.

Local build using Ansible
---
The local Ansible build mechanism is useful for creating a virtualized cluster that acts in as many ways as possible like a real hardware cluster. To this end, it sacrifices convenience and speed for correctness, so there are a number of manual steps that must be taken when standing up the bootstrap node. A few concessions must still be made in order to avoid requiring extra services or network changes to be set up on the build host, but for the most part this virtualized cluster will have the same behavior as a real cluster. Please see **ansible_local_build_guide.md** for additional information on this build path.

Physical build using Ansible
---
The physical Ansible build mechanism is what is used to stand up hardware clusters using the BCPC software stack. This can be run on anything from NUCs to real rackmounted servers. The main difference between the local build and the physical build is that **no Internet connection whatsoever** is presumed to be accessible for any of the servers being turned into a hardware cluster during build-out. You will still, of course, require an Internet connection on your local host to retrieve various prerequisites and mirror the apt repositories, as well as a way to transfer all this data to the host that will be orchestrating the cluster build-out. Please see **ansible_hardware_build_guide.md** for additional information on this build path.
