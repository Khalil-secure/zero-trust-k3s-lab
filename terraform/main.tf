terraform {
  required_version = ">= 1.3.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

# ── PROVIDER ──
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# ── DATA SOURCES ──
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id   = var.compartment_ocid
  operating_system = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape            = var.instance_shape
  sort_by          = "TIMECREATED"
  sort_order       = "DESC"
}

# ── NETWORK ──
resource "oci_core_vcn" "zero_trust_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "zero-trust-vcn"
  dns_label      = "zerotrust"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.zero_trust_vcn.id
  display_name   = "zero-trust-igw"
  enabled        = true
}

resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.zero_trust_vcn.id
  display_name   = "zero-trust-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_subnet" "public_subnet" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.zero_trust_vcn.id
  cidr_block        = "10.0.1.0/24"
  display_name      = "zero-trust-public-subnet"
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public_rt.id
  security_list_ids = [oci_core_security_list.k3s_security_list.id]
}

# ── SECURITY LIST ──
resource "oci_core_security_list" "k3s_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.zero_trust_vcn.id
  display_name   = "k3s-security-list"

  # Allow all outbound
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # k3s API server
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # HTTP/HTTPS for ingress
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # WireGuard VPN
  ingress_security_rules {
    protocol = "17"
    source   = "0.0.0.0/0"
    udp_options {
      min = 51820
      max = 51820
    }
  }

  # Istio
  ingress_security_rules {
    protocol = "6"
    source   = "10.0.0.0/16"
    tcp_options {
      min = 15000
      max = 15010
    }
  }

  # Grafana dashboard
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 3000
      max = 3000
    }
  }

  # Internal cluster traffic
  ingress_security_rules {
    protocol = "all"
    source   = "10.0.0.0/16"
  }
}

# ── K3S MASTER NODE ──
resource "oci_core_instance" "k3s_master" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  shape               = var.instance_shape
  display_name        = "k3s-master"

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    assign_public_ip = true
    display_name     = "k3s-master-vnic"
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data = base64encode(templatefile("${path.module}/scripts/install-k3s-master.sh", {
      node_token = random_string.k3s_token.result
    }))
  }

  freeform_tags = {
    "project"     = "zero-trust-k8s-lab"
    "role"        = "k3s-master"
    "environment" = "lab"
  }
}

# ── K3S WORKER NODES ──
resource "oci_core_instance" "k3s_worker" {
  count               = var.node_count
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  shape               = var.instance_shape
  display_name        = "k3s-worker-${count.index + 1}"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    assign_public_ip = true
    display_name     = "k3s-worker-${count.index + 1}-vnic"
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data = base64encode(templatefile("${path.module}/scripts/install-k3s-worker.sh", {
      master_ip  = oci_core_instance.k3s_master.public_ip
      node_token = random_string.k3s_token.result
    }))
  }

  freeform_tags = {
    "project"     = "zero-trust-k8s-lab"
    "role"        = "k3s-worker"
    "environment" = "lab"
  }
}

# ── RANDOM TOKEN FOR K3S ──
resource "random_string" "k3s_token" {
  length  = 32
  special = false
}

# ── OUTPUTS ──
output "master_public_ip" {
  description = "Public IP of k3s master node"
  value       = oci_core_instance.k3s_master.public_ip
}

output "worker_public_ips" {
  description = "Public IPs of k3s worker nodes"
  value       = oci_core_instance.k3s_worker[*].public_ip
}

output "k3s_api_endpoint" {
  description = "k3s API server endpoint"
  value       = "https://${oci_core_instance.k3s_master.public_ip}:6443"
}

output "ssh_master" {
  description = "SSH command for master node"
  value       = "ssh ubuntu@${oci_core_instance.k3s_master.public_ip}"
}
