variable "admin_ssh_public_key" {
  type        = string
  description = "Public SSH key installed in the guest. Pass at runtime; no private key enters state."
}
