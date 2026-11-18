variable "kubeconfigpath" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfigcontext" {
  description = "Kubernetes context to use (leave empty for current-context)"
  type        = string
  default     = ""
}

variable "gitusername" {
  description = "Username for Git repository authentication"
  type        = string
  default     = "git"
}

variable "gitpassword" {
  description = "Password or Personal Access Token for Git repository authentication (optional if repo is public)"
  type        = string
  default     = ""
  sensitive   = true
}
