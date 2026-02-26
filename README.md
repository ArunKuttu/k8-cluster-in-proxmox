# Deploy a K8 cluster in Proxmox using Terraform and Ansible
Running a kube cluster in any public cloud provider is a costly business.
There are many ways to deploy a local cluster with virtualbox, kind etc.
However I wanted to use Proxmox with my home server and I could not find any complete example of deploying a fully automated cluster using Terraform and Ansible.
So I created this repo.
This is not production grade at all but perfect for running a 3 node cluster at home.


# Pre-requisits
- Create a user with API token in Proxmox following this guide https://registry.terraform.io/providers/Telmate/proxmox/latest/docs
     Steps to do using the Doc

Proxmox 9 and Newer

         pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Pool.Audit Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU   VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"
         pveum user add terraform-prov@pve --password <password>
         pveum aclmod / -user terraform-prov@pve -role TerraformProv

Proxmox 8 and Older

     pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Migrate VM.PowerMgmt SDN.Use"
     pveum user add terraform-prov@pve --password <password>
     pveum aclmod / -user terraform-prov@pve -role TerraformProv


Using an API Token (Recommended)

     pveum user token add terraform-prov@pve mytoken


Creating the connection via username and password

     export PM_USER="terraform-prov@pve"
     export PM_PASS="password"
     
- Make sure NOT to enable privilege separation for the API key. Otherwise Terraform will not be able to find the VM template.
- VM template (follow steps below to create a template)
- `CIDR` range to setup static IPs for the cluster nodes. Below are the default IPs.
```
master  192.168.193.20
worker0 192.168.193.30
worker1 192.168.193.31
```
- Terraform and Ansible

# How to use this code
- Make sure you have all the pre-requisites
- Clone this repo
- Export `PM_API_TOKEN_ID` and `PM_API_TOKEN_SECRET`
- Run `Terraform init` from the root folder
- Run `Terraform apply`
- `SSH` into nodes as needed with user `jay`

# Notes
- Make sure to install a `CNI` plugin. Cilium and WeaveNet are some of the options.
- If you want to change the CIDR range/username etc, you may have to dig a little bit. I will update this documentation to make it easier at some point.
- Check the locations of the SSH keys, I used the usual default locations and file names ```( ~/.ssh/id_rsa )```
- Use MetalLB https://metallb.universe.tf/installation/ to play with Ingress and Ingress Controller.
- Use https://github.com/kubernetes-sigs/metrics-server metrics server, but make sure to update the deployment with ```--kubelet-insecure-tls``` arg to get it running.
## How to create a VM template in Proxmox
```
# download the cloud image
     cd /var/lib/vz/template/iso
# latest LTS version
     wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# create a new VM
     qm create 7000 \
       --name ubuntu-2204-jammy-cloudinit-template \
       --memory 2048 \
       --cores 2 \
       --net0 virtio,bridge=vmbr0 \
       --scsihw virtio-scsi-pci

#Import Cloud Image as SCSI Disk

     qm set 7000 --scsi0 local-lvm:0,import-from=/path/to/bionic-server-cloudimg-amd64.img
#Add Cloud-Init CD-ROM drive

The next step is to configure a CD-ROM drive, which will be used to pass the Cloud-Init data to the VM.

      qm set 7000 --ide2 hdd1tb:cloudinit

To be able to boot directly from the Cloud-Init image, set the boot parameter to order=scsi0 to restrict BIOS to boot from this disk only. This will speed up booting, because VM BIOS skips the testing for a bootable CD-ROM.

     qm set 7000 --boot order=scsi0

For many Cloud-Init images, it is required to configure a serial console and use it as a display. If the configuration doesn’t work for a given image however, switch back to the default display instead.

     qm set 9000 --serial0 socket --vga serial0

In a last step, it is helpful to convert the VM into a template. From this template you can then quickly create linked clones. The deployment from VM templates is much faster than creating a full clone (copy).

     qm template 7000


#Testing creating VM Deployment

     qm clone 7000 123 --name ubuntu2

     qm start 123
     qm set 123 --ciuser username
     qm set 123 --cipassword password
     qm set 123 --delete serial0
     qm set 123 --vga std  (For getting proxmox console)
     qm stop 123
     qm stop 123

#### Reference: #####
https://pve.proxmox.com/pve-docs/chapter-qm.html#_preparing_cloud_init_templates



