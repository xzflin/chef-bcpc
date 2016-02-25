Installing Liberty
===

Liberty support is now included in BCPC. The following caveats apply:
* We welcome bug reports for issues encountered with Liberty, but Liberty will not become the default version of OpenStack installed by BCPC until BCPC 6.0. Kilo remains the default and recommended version for use with BCPC 5.x.
* Both fresh installs of Liberty and upgrading from Kilo to Liberty have been tested. To trigger an upgrade, change **bcpc.openstack_release** to `liberty` and re-chef the cluster.
* While steps have been taken to ensure that the upgrade process is as painless as possible, the upgrade will still effectively be a cluster-down situation. Please plan appropriately when deciding to upgrade to Liberty.
* Recommended API versions have changed, and certain API version choices made for Kilo no longer hold for Liberty. Please use the versions specified in the JSON segment below. The upgrade process will automatically remove and replace outdated endpoints as needed.
* Notes about API versions:
  * Cinder API v1 is no longer supported in Liberty. Due to a bug in Horizon, both the **volume** and **volumev2** endpoints are still required, but should both be set to use the v2 API.
  * Both the v2.0 and v3 Keystone APIs *should* work, but v3 is the one that has primarily been tested with Liberty, so upgrading is strongly recommended.

To enable Liberty, merge the following JSON into your environment file:

```
{
  "bcpc": {
    "openstack_release": "liberty",
    "catalog": {
      "identity": {
        "uris": {
          "admin": "v3",
          "internal": "v3",
          "public": "v3"
        }
      },
      "compute": {
        "uris": {
          "admin": "v2/%(tenant_id)s",
          "internal": "v2/%(tenant_id)s",
          "public": "v2/%(tenant_id)s"
        }
      },
      "volume": {
        "uris": {
          "admin": "v2/%(tenant_id)s",
          "identity": "v2/%(tenant_id)s",
          "public": "v2/%(tenant_id)s"
        }
      }
    }
  }
}
```

If you are using a local mirror to build rather than package repositories on the Internet, please ensure that you have mirrored the Liberty repositories locally prior to attempting a build.
