Frequently asked questions
===

Can I do a build without being connected to the Internet?
---
Unfortunately, due to an issue with **setuptools** (a popular Python module used for installing packages), it is not possible at the moment to do a build from scratch without Internet access. Specifically, **setuptools** tries to reach out to PyPI (a Python package repository) to obtain a list of dependencies for a package. Once this is resolved, if you have all apt repositories mirrored and can provide local DNS/NTP resolution from the host computer, it should indeed be possible to do a fully disconnected build.

Can I use VMware instead of VirtualBox for a local cluster?
---
Not at present, but it is something we'd like to offer.

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