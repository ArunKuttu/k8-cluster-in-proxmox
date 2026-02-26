##################################
# Terraform & Providers
##################################

terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.11"
    }
    local = {
      source = "hashicorp/local"
    }
    null = {
      source = "hashicorp/null"
    }
    template = {
      source = "hashicorp/template"
    }
  }
}

provider "proxmox" {
  pm_api_url      = "https://192.168.1.3:8006/api2/json"
  pm_tls_insecure = true
  # Authentication via:
  #export PM_API_TOKEN_ID=
  #export PM_API_TOKEN_SECRET=
}

##################################
# Cloud-init template rendering
##################################

data "template_file" "cloud_init_master" {
  template = file("${path.module}/cloud-init/master.yaml")

  vars = {
    ssh_key = file(var.ssh_public_key_path)
  }
}

data "template_file" "cloud_init_worker" {
  count    = var.worker_count
  template = file("${path.module}/cloud-init/worker.yaml")

  vars = {
    ssh_key = file(var.ssh_public_key_path)
  }
}

##################################
# Write rendered cloud-init locally
##################################

resource "local_file" "cloud_init_master" {
  content  = data.template_file.cloud_init_master.rendered
  filename = "${path.module}/cloud_init_master_generated.yaml"
}

resource "local_file" "cloud_init_worker" {
  count    = var.worker_count
  content  = data.template_file.cloud_init_worker[count.index].rendered
  filename = "${path.module}/cloud_init_worker_${count.index}.yaml"
}

##################################
# Copy cloud-init files to Proxmox
##################################

resource "null_resource" "cloud_init_master" {
  connection {
    type        = "ssh"
    user        = "root"
    host        = "192.168.1.3"
    private_key = file(var.private_key_path)
  }

  provisioner "file" {
    source      = local_file.cloud_init_master.filename
    destination = "/var/lib/vz/snippets/cloud_init_master.yaml"
  }
}

resource "null_resource" "cloud_init_worker" {
  count = var.worker_count

  connection {
    type        = "ssh"
    user        = "root"
    host        = "192.168.1.3"
    private_key = file(var.private_key_path)
  }

  provisioner "file" {
    source      = local_file.cloud_init_worker[count.index].filename
    destination = "/var/lib/vz/snippets/cloud_init_worker_${count.index}.yaml"
  }
}

##################################
# Kubernetes Master VM
##################################

resource "proxmox_vm_qemu" "master" {
  depends_on = [null_resource.cloud_init_master]

  name        = "k8s-master"
  target_node = var.proxmox_host
  clone       = var.template_name
  vmid        = 200

  cores   = 2
  sockets = 1
  memory  = 4096

  disk {
    size    = "30G"
    type    = "scsi"
    storage = "firestore"
  }

  lifecycle {
    ignore_changes = [network]
  }

  cicustom  = "user=local:snippets/cloud_init_master.yaml"
  ipconfig0 = "ip=192.168.1.6/24,gw=192.168.1.1"
}

##################################
# Kubernetes Worker VMs
##################################

resource "proxmox_vm_qemu" "worker" {
  count      = var.worker_count
  depends_on = [null_resource.cloud_init_worker]

  name        = "k8s-worker-${count.index}"
  target_node = var.proxmox_host
  clone       = var.template_name
  vmid        = 300 + count.index

  cores   = 2
  sockets = 1
  memory  = 4096

  disk {
    size    = "30G"
    type    = "scsi"
    storage = "firestore"
  }

  lifecycle {
    ignore_changes = [network]
  }

  cicustom  = "user=local:snippets/cloud_init_worker_${count.index}.yaml"
  ipconfig0 = "ip=192.168.1.${7 + count.index}/24,gw=192.168.1.1"
}

##################################
# Optional: Ansible handover
##################################

resource "null_resource" "ansible_handover" {
  depends_on = [
    proxmox_vm_qemu.master,
    proxmox_vm_qemu.worker
  ]

  provisioner "local-exec" {
    command = "ansible-playbook -i ansible/inventory --private-key ${var.private_key_path} ansible/k8_cluster_setup.yaml"
  }
}
