

function install_cluster {
environment=${1-Test-Laptop}
ip=${2-10.0.100.3}
  # VMs are now created - if we are using Vagrant, finish the install process.
  if hash vagrant 2> /dev/null ; then
    # N.B. As of Aug 2013, grub-pc gets confused and wants to prompt re: 3-way
    # merge.  Sigh.
    #vagrant ssh -c "sudo ucf -p /etc/default/grub"
    #vagrant ssh -c "sudo ucfr -p grub-pc /etc/default/grub"
    vagrant ssh -c "test -f /etc/default/grub.ucf-dist && sudo mv /etc/default/grub.ucf-dist /etc/default/grub" || true
    # Duplicate what d-i's apt-setup generators/50mirror does when set in preseed
    if [ -n "$http_proxy" ]; then
      if ! vagrant ssh -c "grep -z '^Acquire::http::Proxy ' /etc/apt/apt.conf"; then
        vagrant ssh -c "echo 'Acquire::http::Proxy \"$http_proxy\";' | sudo tee -a /etc/apt/apt.conf"
      fi

      # write the proxy to a known absolute location on the filesystem so that it can be sourced by build_bins.sh (and maybe other things)
      PROXY_INFO_SH="/home/vagrant/proxy_info.sh"
      if ! vagrant ssh -c "test -f $PROXY_INFO_SH"; then
        vagrant ssh -c "echo -e 'export http_proxy=$http_proxy\nexport https_proxy=$https_proxy' | sudo tee -a $PROXY_INFO_SH"
       fi
      CURLRC="/home/vagrant/.curlrc"
      if ! vagrant ssh -c "test -f $CURLRC"; then
        vagrant ssh -c "echo -e 'proxy = $http_proxy' | sudo tee -a $CURLRC"
      fi
      GITCONFIG="/home/vagrant/.gitconfig"
      if ! vagrant ssh -c "test -f $GITCONFIG"; then
        vagrant ssh -c "echo -e '[http]\nproxy = $http_proxy' | sudo tee -a $GITCONFIG"
      fi

      # copy any additional provided CA root certificates to the system store
      # note that these certificates must follow the restrictions of update-ca-certificates (i.e., end in .crt and be PEM)
      CUSTOM_BASE="custom"
      CUSTOM_CA_DIR="/usr/share/ca-certificates/$CUSTOM_BASE"
      for CERT in $(ls -1 $BASE_DIR/cacerts); do
        vagrant ssh -c "sudo mkdir -p $CUSTOM_CA_DIR"
        vagrant ssh -c "if [[ ! -f $CUSTOM_CA_DIR/$CERT ]]; then sudo cp /chef-bcpc-host/cacerts/$CERT $CUSTOM_CA_DIR/$CERT; fi"
        vagrant ssh -c "echo $CUSTOM_BASE/$CERT | sudo tee -a /etc/ca-certificates.conf"
      done
      vagrant ssh -c "sudo /usr/sbin/update-ca-certificates"
    fi
    echo "Bootstrap complete - setting up Chef server"
    echo "N.B. This may take approximately 30-45 minutes to complete."
    ./bootstrap_chef.sh --vagrant-remote $ip $environment
    ./enroll_cobbler.sh
  else
    ./non_vagrant_boot.sh
  fi
}
