Installing Liberty
===

Liberty support is now **experimentally** included in BCPC. The following caveats apply:
* This support is **entirely experimental**. We welcome bug reports for issues encountered with it, but Liberty will not become the recommended version of OpenStack to use with BCPC until BCPC 6.0.
* Only fresh installs of Liberty have been tested. Attempting to upgrade in place will probably result in a dreadful bloodbath and an unusable cluster. (It is intended that BCPC 6.0 will include a way to upgrade in place if possible.)
* Recommended API versions have changed, and certain API version choices made for Kilo no longer hold for Liberty:
  * Cinder API v1 is no longer supported in Liberty. Due to a bug in Horizon, both the **volume** and **volumev2** endpoints are still required, but should both be set to use the v2 API.
  * Both the v2.0 and v3 Keystone APIs should work, but v3 is the one that has primarily been tested with Liberty, so upgrading is recommended.

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
