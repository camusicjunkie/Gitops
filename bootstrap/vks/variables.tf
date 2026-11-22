variable "cluster_name" {
  type        = string
  description = "CAPI Cluster name: <network>-<env>-<color>"

  validation {
    condition     = can(regex("^[a-z0-9]+-(staging|production|management)-(blue|green)$", var.cluster_name))
    error_message = "Use <network>-<env>-<color>, e.g. neta-staging-green."
  }
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to the target cluster's kubeconfig (written by the pipeline)"
}

variable "network_domain" {
  type        = string
  description = "Network DNS suffix (e.g. corp.local). Set per GitLab instance, never committed."
}

variable "bootstrap_revision" {
  type        = number
  default     = 1
  description = "Bump to force the bootstrap Job to re-run without other changes"
}

variable "harbor_registry" {
  type        = string
  description = "Container registry host (from GitLab Harbor integration HARBOR_HOST)"
}

variable "harbor_project" {
  type        = string
  default     = "platform"
  description = "Harbor project name (from GitLab Harbor integration HARBOR_PROJECT)"
}

variable "harbor_bootstrap_image" {
  type        = string
  default     = "flux/flux-operator-bootstrap"
  description = "Image path for flux-operator-bootstrap inside <harbor_registry>/<harbor_project>"
}

variable "harbor_operator_chart" {
  type        = string
  default     = "flux/charts/flux-operator"
  description = "Chart path for flux-operator inside <harbor_registry>/<harbor_project>"
}

variable "git_repo_url" {
  type        = string
  description = "Fleet Git repository URL for Flux sync. Set per GitLab instance, never committed."
}

variable "gitlab_deploy_token_username" {
  type      = string
  sensitive = true
}

variable "gitlab_deploy_token" {
  type      = string
  sensitive = true
}

variable "image_automation_git_token_username" {
  type      = string
  sensitive = true
  default   = ""
}

variable "image_automation_git_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "GitLab Project/Group Access Token (write_repository scope) for ImageUpdateAutomation; stored as image-automation-push on management clusters only"
}

variable "harbor_ca" {
  type        = string
  default     = ""
  description = "PEM CA of Harbor's certificate (stored as harbor-ca in flux-system, key ca.crt). Required on management clusters: every ImageRepository there trusts Harbor through it, since Flux's controllers do not see the nodes' trust."
}

variable "devcontainer_repo_url" {
  type        = string
  default     = ""
  description = "Devcontainer repository URL (k8scontainer) on this network's GitLab, as DEVCONTAINER_REPO_URL in flux-runtime-info. Management clusters only. Set per GitLab instance, never committed."
}

variable "devcontainer_deploy_token_username" {
  type      = string
  sensitive = true
  default   = ""
}

variable "devcontainer_deploy_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "read_repository token for the devcontainer repository (stored as devcontainer-git in flux-system); management clusters only"
}

variable "devcontainer_push_token_username" {
  type      = string
  sensitive = true
  default   = ""
}

variable "devcontainer_push_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "write_repository token for the devcontainer repository's image automation (stored as devcontainer-git-push in flux-system); management clusters only"
}

variable "harbor_robot_username" {
  type      = string
  sensitive = true
}

variable "harbor_robot_token" {
  type      = string
  sensitive = true
}

variable "sops_age_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Private age key for Flux SOPS decryption (stored as sops-age Secret in flux-system)"
}
