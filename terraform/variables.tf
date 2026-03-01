# Oracle Cloud Authentication
variable "tenancy_ocid" {
  description = "OCID of the tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the user"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API key"
  type        = string
}

variable "private_key_path" {
  description = "Path to the private key file"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "Oracle Cloud region"
  type        = string
  default     = "eu-marseille-1"
}

# Compute
variable "compartment_ocid" {
  description = "OCID of the compartment"
  type        = string
}

variable "instance_shape" {
  description = "Shape of the compute instance"
  type        = string
  default     = "VM.Standard.A1.Flex" # ARM — free tier
}

variable "instance_ocpus" {
  description = "Number of OCPUs"
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Memory in GB"
  type        = number
  default     = 12
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "node_count" {
  description = "Number of k3s worker nodes"
  type        = number
  default     = 1
}
