#Bloomberg Clustered Private Cloud - Network Architecture v1.0

##Introduction 

This document defines the networks and related infrastructure necessary to 
build a physical OpenStack cluster using Bloomberg's 'chef-bcpc' OpenStack 
distribution. 

##Rationale

Most BCPC cluster builds happen on VirtualBox during normal
development, for both speed of build and convenience. When working
with VirtualBox, the chef-bcpc scripts are able to automagically
produce suitable networks and routers for running a BCPC cluster by
just configuring VirtualBox itself. For this reason, the non-code
documentation provided on what networks are expected and how to build
them is minimal.

When building a BCPC cluster on real hardware (discrete servers,
switches, routers), however, there are some very specific requirements
to be met by the network build before a cluster can be built, and
discrete networking hardware is not standardised enough for this to be
scripted in a universal way. This document attempts to provide enough
info to build such networks, enabling a physical BCPC cluster build.

##Required Networks

Running BCPC clusters require four core data networks to be configured
on the cluster switch(es) and router(s), but typically use 3 or even
just 2 physical NICs and cabling[1].

Three of the four core BCPC networks use tagged VLANs and so require
switch support for that (802.1Q). For good performance, cluster
members typically need multiple high-speed NICs (10 or even 40Gb/s)
given the fully converged BCPC architecture ; fully converged, in this
case, meaning that many nodes both host Ceph content and virtual
machines (VMs) and so see both internal storage traffic (such as Ceph
replication traffic) AND VM "north-south" traffic i.e. off-cluster
traffic such as webserver traffic to the outside world.

Note : BCPC Cluster builds also typically require a 5th network for
machine management (unless you use a lot of keyboards, mice and
screens!). The management console ( 'BMC') supporting IPMI or similar
vendor-specific interfaces for controlling power, boot order etc will
often be on this separate network (sometimes known as the "out of
band" or "OOB" network), however this document does not cover the OOB
network.

[1] running on < 3 physical NICs is possible, see appendix A

##BCPC Cluster networks : names, sample traffic

The four data networks on a BCPC cluster are:

- Management network ("management" in the Chef attributes)

  example : ssh to hypervisor hosts

- Fixed or private IP network ("fixed" in the Chef attributes)

  example: intra-tenancy traffic between VMs in same OpenStack tenancy

- Float IP network ("floating" in the Chef attributes)

  example : traffic to floating IP addresses on VM instances on the cluster

- Storage network ("storage" in the Chef attributes)

  example : Ceph monitor election traffic, Ceph OSD replication traffic

##Layer 2 spanning

In this version of the BCPC network architecture, all networks are
required to be simply-connected internally at Layer 2 (the storage
network might not technically need this but we ignore this in V1).

For small clusters, this simply means the cluster switch(es) must be
big enough for all hosts, or at least "play nice" together with
spanning tree. For larger clusters, particularly if high reliability
is a requirement, this requires some type of explicit Layer 2 spanning
architecture (e.g. leaf/spine using MC-LAG) so as to extend the Layer
2 (broadcast) domain across multiple switches.

##Routing

A BCPC cluster also requires a local Layer 3 router, both to forward
traffic between the cluster networks and for north-south
traffic. Modern data center class switches will be capable of this,
but if using pure Layer 2 cluster switches, a simple linux-based
router can easily be configured for this given network access on a
"trunk port". As an example the bootstrap node can be configured to
provide routing for the cluster if connected to a trunk port.

Note: If a "trunk port" is not explicitly supported by the switch, you just
need to configure a port which will see all BCPC VLANs (mgmt, storage,
fixed, float) so as to be able to see and forward any packet.

##BCPC detailed network requirements.

Minimum IP range sizes are discussed in the following sections for
cases where they are constrained, however if possible it is better to
find suitably large ranges from the start (for example /18s or bigger)
so that your cluster capacity growth and/or number of VMs is not
constrained by running out of addresses.

### Management Network

The management network must be large enough for every potential
physical host in the cluster and any supporting machines such as the
bootstrap node, plus the management network gateway.

For maximum compatibility with boot ROMs during PXE boot, the mgmt
network is always the native (untagged) VLAN. Given a choice, the mgmt
network can run on a lower-bandwidth link than the other networks, but
will still benefit from good bandwidth, for example during a) PXE
booting hosts from the bootstrap node b) glance image uploading and
possibly other bandwidth-hungry OpenStack control plane operations.

This network requires a defined gateway, routing and must be
externally reachable for hypervisor hosts to be reachable for
OpenStack and Ceph administration. The mgmt network subnet and NIC are
defined in the Chef attributes, typically in the environment file.

### Fixed Network

Every VM receives a unique fixed IP address for its
lifetime. Openstack documentation calls this either the "fixed" or the
"private" address.

Since the BCPC fixed network uses private addresses only seen within
the cluster i.e. the same Layer 2 broadcast domain, it does not
require external routing, so can be arbitrarily large e.g. a /16. An
RFC1918-compliant address range would be a good choice.

Each tenancy receives a distinct VLAN tag for its fixed network
traffic. Traffic originates from a VM on its fixed IP with this VLAN
tag and reaches the local hypervisor host via a linux bridge. If the
traffic is for a destination outside of the tenant network it is
rewritten to appear to come from a float IP address (either the one
the VM has, or failing that the float assigned to the hypervisor
host). Purely intra-tenancy traffic is not rewritten, however, so the
packets source and destination addresses, as well as its VLAN tag, are
all seen by the cluster switches, so the cluster switches must allow
traffic on these VLANs to pass.

In summary then, the fixed network should be a private non-routable
network but the switches must support tagged VLANs for every
individual tenancy to communicate privately, as well as the "float"
tagged VLAN which supports intra-tenancy and north-south (off-cluster)
traffic (see next section).

Fixed (tenant) network VLAN IDs are chosen sequentially starting at an
ID you specify in the Chef attributes (typically in the environment
file) along with the subnet definition.

### Float Network

The float network must be large enough to support the sum of every
floating IP address provisioned to VMs PLUS one address for each
physical hypervisor, PLUS the float network gateway (N.B. this implies
a larger minimum size than the management or storage networks, for
example).

This network is implemented as a tagged VLAN and assigned to a high
bandwidth NIC if available since all VM traffic passes on this
interface. 

The chef-bcpc recipes support setting an increased MTU for the float
network, allowing jumbo packets for maximum throughput. However, since
the float network may serve north-south traffic, care must be taken to
use a "safe" MTU i.e. one which wont break any possible clients. You
also should never exceed the maximum MTU supported by your cluster
switches.

This network needs a defined gateway and routing since it must be
externally reachable for VMs to be reachable on their floating IP
addresses i.e. for them to be able to serve traffic. The VLAN ID is
specified in the Chef attributes, typically the environment file along
with the subnet definition.

### Storage Network

The storage network only needs to be large enough to provide an
address for every Ceph mon node and every Ceph OSD node, plus the
storage network gateway.  By convention, then, it is typically sized
to be the same size as the mgmt network assuming 100% converged
topology (every cluster member a Ceph node).

This network is also implemented as a tagged VLAN and assigned to a
high bandwith NIC (if available) to handle the Ceph monitor traffic
(e.g. elections, heartbeats) and Ceph OSD traffic
(e.g. replication). 

Setting the MTU is again supported for the storage network in the
recipes and is particularly important here since the storage network
will typically be the busiest of the three cluster networks. Once
again : don't set an MTU bigger than what your switches can handle. If
after testing you find 9000 byte MTUs work, that will be particularly
beneficial for bulky storage replication traffic.

This network uses a gateway only as a sanity check at build-time
(cluster nodes ping each network gateway upon initial build to check
connectivity) and need not be externally reachable, as it is an
internal-only network during normal cluster operation. Therefore
routing for this network is not technically required. The storage
network subnet is defined as usual in the Chef attributes, typically
in the environment file.

###Appendix A

####Moving the mgmt network onto the same NIC as float

Using the default NIC with its own link to the switch can be easier to
configure when first attempting to build a physical cluster. For
example a hypervisor host might have a built-in 1Gb link and an add-in
high-speed additional network card such as a dual 10 or 40Gb/s
adapter. Linux driver stability and device naming tends to be very
stable for built-in NICs like this. For this reason the default
assumption in chef-bcpc is that the management network is wired
separately to the float, fixed and storage networks. This allows you
to get your operating system PXE-booted to each host without even
configuring high-bandwidth links nor VLANs.

However, you can reduce your cabling needs and switch port consumption
by one link and port per host if the mgmt network runs on the same
link as the float/fixed networks : In your cluster environment file
simply mention the same NIC name for the mgmt, the float and the fixed
networks but for the float use the variant with the VLAN suffix. The
recipes then configure a tagged VLAN interface permanently on the host
for the float traffic, whereas the fixed network's tagged VLAN
interfaces come and go as nova network builds and tears down tenant
networks and virtual NICs bridged to the physical NIC assigned to the
float network.

###Appendix B

####Network summary table

#####default

|        |tagged |  routed |  nic assign|          
| ---    | ---   | ---     | --- |
|mgmt    |  n    |    y    |  1|
|fixed   |  y    |    n    |  2|
|float   |  y    |    y    |  2|
|storage |  y    |    n    |  3|

#####alternate

note: if you only use two NICs, mgmt, fixed and float should be on the
first NIC and storage on the second i.e.

|        |tagged |  routed |  nic assign|          
| ---    | ---   | ---     | --- |
|mgmt    |  n    |    y    |  1|
|fixed   |  y    |    n    |  1|
|float   |  y    |    y    |  1|
|storage |  y    |    n    |  2|

