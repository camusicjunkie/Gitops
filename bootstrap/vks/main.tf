terraform {
  backend "http" {}

  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
  }
}

locals {
  # <network>-<env>-<color> -> ["<network>", "<env>", "<color>"]
  cluster_parts = split("-", var.cluster_name)
  cluster_env   = local.cluster_parts[1]
  cluster_color = local.cluster_parts[2]

  harbor_dockerconfigjson = jsonencode({
    auths = {
      (var.harbor_registry) = {
        username = var.harbor_robot_username
        password = var.harbor_robot_token
        auth     = base64encode("${var.harbor_robot_username}:${var.harbor_robot_token}")
      }
    }
  })
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

module "flux_operator_bootstrap" {
  # For air-gapped environments, mirror this module to internal GitLab and update source:
  # source = "git::https://<gitlab-host>/mirrors/terraform-kubernetes-flux-operator-bootstrap.git?ref=v0.8.0"
  source  = "controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes"
  version = "~> 0.8.0"

  revision = var.bootstrap_revision

  job = {
    image = {
      repository = "${var.harbor_registry}/${var.harbor_project}/${var.harbor_bootstrap_image}"
    }
  }

  gitops_resources = {
    operator_chart = {
      repository = "${var.harbor_registry}/${var.harbor_project}/${var.harbor_operator_chart}"
    }
    instance_yaml = templatefile("${path.root}/../../clusters/${local.cluster_env}/flux-system/instance.yaml", {
      HARBOR_REGISTRY = var.harbor_registry
      HARBOR_PROJECT  = var.harbor_project
      GIT_REPO_URL    = var.git_repo_url
    })
  }

  managed_resources = {
    secrets_yaml = <<-YAML
      apiVersion: v1
      kind: Secret
      metadata:
        name: flux-system
      type: Opaque
      stringData:
        username: '${replace(var.gitlab_deploy_token_username, "'", "''")}'
        password: '${replace(var.gitlab_deploy_token, "'", "''")}'
      ---
      apiVersion: v1
      kind: Secret
      metadata:
        name: harbor-pull
      type: kubernetes.io/dockerconfigjson
      stringData:
        .dockerconfigjson: '${replace(local.harbor_dockerconfigjson, "'", "''")}'
      ${local.cluster_env == "management" && var.image_automation_git_token != "" ? <<-PUSH
      ---
      apiVersion: v1
      kind: Secret
      metadata:
        name: image-automation-push
      type: Opaque
      stringData:
        username: '${replace(var.image_automation_git_token_username, "'", "''")}'
        password: '${replace(var.image_automation_git_token, "'", "''")}'
      PUSH
    : ""}
      ${var.sops_age_key != "" ? <<-SOPS
      ---
      apiVersion: v1
      kind: Secret
      metadata:
        name: sops-age
      type: Opaque
      stringData:
        age.agekey: |
          ${indent(4, trimspace(var.sops_age_key))}
      SOPS
  : ""}
    YAML

  runtime_info = {
    labels = {
      "reconcile.fluxcd.io/watch" = "Enabled"
    }
    data = {
      NETWORK_DOMAIN  = var.network_domain
      CLUSTER_NAME    = var.cluster_name
      CLUSTER_ENV     = local.cluster_env
      CLUSTER_COLOR   = local.cluster_color
      HARBOR_REGISTRY = var.harbor_registry
      HARBOR_PROJECT  = var.harbor_project
      GIT_REPO_URL    = var.git_repo_url
    }
  }
}
}
