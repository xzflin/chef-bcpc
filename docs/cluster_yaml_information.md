cluster.yaml
===

cluster.yaml format
---
`cluster.yaml` is a YAML file that describes the hardware layout of your cluster. A sample layout:
```
cluster_name: TEST
nodes:
  fake-node-r06n01:
    domain: completelyfake.example
    hardware_type: Virtual
    ip_address: 131.81.229.220
    ipmi_address: 62.185.178.18
    mac_address: 21:b0:d5:9b:f8:3b
    role: bootstrap
  fake-node-r06n02:
    domain: completelyfake.example
    hardware_type: Virtual
    ip_address: 127.228.36.77
    ipmi_address: 218.161.198.210
    mac_address: 18:c2:93:42:a5:cd
    role: work
```
* Valid roles are: **bootstrap**, **head**, **work**, **work-ephemeral**, or **reserved**.
* The MAC address is used by Cobbler for PXE booting.
* The hardware type is interpolated into the string **BCPC-Hardware-[hardware_type]** when selecting a role to represent the node's hardware type.
