
def optimal_pgs_per_node
  power_of_2(get_ceph_osd_nodes.length * node['bcpc']['ceph']['pgs_per_node'] / node['bcpc']['ceph']['rgw']['replicas'] * node['bcpc']['ceph']['rgw']['portion'] / 100)
end
