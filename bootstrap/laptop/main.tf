# Optional Git credentials secret for private GitRepository sync
resource "kubernetes_secret" "flux_system" {
  count = var.gitpassword != "" ? 1 : 0

  metadata {
    name      = "flux-system"
    namespace = "flux-system"
  }

  data = {
    username = var.gitusername
    password = var.gitpassword
  }

  type = "Opaque"
}

# The official Flux Operator Bootstrap Module (controlplaneio-fluxcd)
module "flux_operator_bootstrap" {
  source  = "controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes"
  version = "~> 0.10.0"

  revision = 1

  gitops_resources = {
    instance_yaml = file("${path.root}/../../clusters/laptop/flux-system/instance.yaml")

    prerequisites = {
      yamls = [
        file("${path.root}/../../clusters/laptop/settings.yaml")
      ]
    }
  }

  depends_on = [kubernetes_secret.flux_system]
}
