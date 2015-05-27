
node['bcpc']['flavors']['enabled'].each do |name, flavor| 
  bcpc_osflavor name do
    memory_mb flavor['memory_mb'] 
    disk_gb   flavor['disk_gb'] 
    vcpus  flavor['vcpus'] 
    ephemeral_gb flavor['ephemeral_gb']
    swap_gb flavor['swap_gb']
    is_public flavor['is_public']
    
  end
end 

node['bcpc']['flavors']['deleted'].each do |name| 
  bcpc_osflavor name do
    action :delete
  end
end
