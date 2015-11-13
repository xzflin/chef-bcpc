Frequently asked questions
===

Can I do a build without being connected to the Internet?
---
Yes! Please read the [Disconnected Build Guide](https://github.com/bloomberg/chef-bcpc/blob/master/docs/disconnected_build_guide.md) for information on how to build a BCPC cluster without access to the Internet.

Can I use VMware instead of VirtualBox for a local cluster?
---

Why is it so slow when running locally?
---
A couple of reasons:

* VirtualBox does not make VT-x available within VMs, so QEMU must use older virtualization techniques that are far less performant.
* In order to keep the footprint of the VMs down so that they can all run on a computer with 16 GB of memory, the default memory allocations are very restrictive, which forces many things into swap (particularly on the head node). If you have more than 16GB of memory, allocating more memory to the cluster nodes, and particularly the head node, can help things out quite a bit.

Where can I read more about the technologies used in BCPC?
---
Please see the top-level README.md file for a comprehensive list of the technologies used in BCPC, with links to the vendor websites. (If you notice that something is not listed that should be, please let us know or submit a pull request so that the project can receive the appropriate credit.)

Can I submit a pull request or issue for *x*?
---
Of course! We welcome pull requests and issues (even better, pull requests that fix issues).
