Vagrant.configure("2") do |config|
  # Base OS
  #config.vm.box = "ubuntu/jammy64"      # AMD64 variant
  config.vm.box = "bento/ubuntu-22.04"   # ARM64 variant exists depending on provider

  # Mount a folder from host → VM
  # host_path : vm_path
  config.vm.synced_folder "/path_to_project", "/vagrant_data"

  # Optional but useful
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
  end

  # Optional: set hostname
  config.vm.hostname = "ubuntu-dev"
end