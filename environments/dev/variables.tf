variable "region" {
  type    = string
  default = "us-east-1"
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "Your IP CIDR for SSH. Use YOUR_IP/32. Default allows all — restrict in production."
  default     = "0.0.0.0/0"
}

variable "public_key" {
  type        = string
  description = "SSH public key. Generate: ssh-keygen -t ed25519 -C 'cloud-security-platform' -f ~/.ssh/cloud-security-platform"
}

variable "db_name" {
  type    = string
  default = "cloud_security_platform"
}

variable "db_username" {
  type    = string
  default = "platform_admin"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "RDS master password — min 8 chars. Never commit this value."
}
