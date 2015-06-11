(The below content was excerpted from the top-level README.md. It may be useful to some people and will be re-edited to be relevant on the next documentation pass.)

These recipes are currently intended for building a BCPC cloud on top of
Ubuntu 14.04 servers using Chef 12. When setting this up in VMs, be sure to
add a few dedicated disks (for ceph OSDs) aside from boot volume. In
addition, it's expected that you have three separate NICs per machine, with
the following as defaults (and recommendations for VM settings):
 - ``eth0`` - management traffic (host-only NIC in VM)
 - ``eth1`` - storage traffic (host-only NIC in VM)
 - ``eth2`` - VM traffic (host-only NIC in VM)

You should look at the various settings in ``cookbooks/bcpc/attributes/default.rb``
and tweak accordingly for your setup (by adding them to an environment file).

Cluster Bootstrap
-----------------

Please refer to the [BCPC Bootstrap Guide](https://github.com/bloomberg/chef-bcpc/blob/master/docs/legacy_bootstrap_doc.md)
for more information about getting a BCPC cluster bootstrapped the hard way

There are provided scripts which set up a Chef and Cobbler server via
[Vagrant](http://www.vagrantup.com/) or on bare metal that permit imaging of
the cluster via PXE.

Once the Chef server is set up, you can bootstrap any number of nodes to get
them registered with the chef server for your environment - see the next
section for enrolling the nodes.

Make a cluster
--------------

To build a new BCPC cluster, you have to start with building a single head node
first. (This assumes that you have already completed the bootstrap process and
have a Chef server available.)  Since the recipes will automatically generate
all passwords and keys for this new cluster, enable the target node as an
``admin`` in the chef server so that the recipes can write the generated info
to a databag.  The databag will be called ``configs`` and the databag item will
be the same name as the environment (``Test-Laptop`` in this example). You only
need to leave the node as an ``admin`` for the first chef-client run. You can
also manually create the databag & item (as per the example in
``data_bags/configs/Example.json``) and manually upload it if you'd rather not
bother with the whole ``admin`` thing for the first run.

So add this first node as the role ``BCPC-Headnode`` and run ``chef-client``
on the target node. After the first one is up, you can add another head
node with:

```
 $ knife bootstrap -E Test-Laptop -r "role[BCPC-Headnode]" -x ubuntu --sudo <IPAddress>
```

If you get an error saying ``403 "Forbidden"`` on the initial run, you 
probably forgot to make the initial headnode client an admin user (see instructions
in bootstrap.md):

```
10.0.100.11 [2013-05-18T13:23:11-04:00] FATAL: Net::HTTPServerException: ruby_block[initialize-ssh-keys] (bcpc::networking line 22) had an error: Net::HTTPServerException: 403 "Forbidden"
```

To enroll a server as a worker node:

```
 $ knife bootstrap -E Test-Laptop -r "role[BCPC-Worknode]" -x ubuntu --sudo <IPAddress>
```

Using a cluster
---------------

Once the nodes are configured and bootstrapped, BCPC services will be
accessible via the floating IP.  (For the Test-Laptop environment, it is
10.0.100.5.)

For example, you can go to ``https://10.0.100.5/horizon/`` for the OpenStack
web interface.  To find the automatically-generated OpenStack credentials, look
in the data bag for your environment under ``keystone-admin-user`` and
``keystone-admin-password``:

```
ubuntu@bcpc-bootstrap:~$ knife data bag show configs Test-Laptop | grep keystone-admin
keystone-admin-password:       abcdefgh
keystone-admin-token:          this-is-my-token
keystone-admin-user:           admin

```

For example, to check on ``Ceph``:

```
ubuntu@bcpc-vm1:~$ ceph -s
   health HEALTH_OK
   monmap e1: 1 mons at {bcpc-vm1=172.16.100.11:6789/0}, election epoch 2, quorum 0 bcpc-vm1
   osdmap e94: 12 osds: 12 up, 12 in
    pgmap v705: 2192 pgs: 2192 active+clean; 80333 KB data, 729 MB used, 227 GB / 227 GB avail
   mdsmap e4: 1/1/1 up {0=bcpc-vm1=up:active}
```
