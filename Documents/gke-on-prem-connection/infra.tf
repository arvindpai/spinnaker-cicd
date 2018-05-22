provider "google" {
  project     = "gke-test1"
  version = "~> 1.12"
}

resource "google_compute_address" "public_ip_1" {
  name = "public-ip-1"
  region = "us-west1"
}

resource "google_compute_address" "public_ip_2" {
  name = "public-ip-2"
  region = "us-central1"
}

variable "shared_secret" {}

module "cloud" {
  source = "./modules/datacenter"
  network_name = "cloud"
  subnet_region = "us-west1"
  ip_cidr_range = "10.1.0.0/16"
  vpn_ip = "${google_compute_address.public_ip_1.address}"
  peer_ip = "${google_compute_address.public_ip_2.address}"
  destination_range = "10.2.0.0/16"
  shared_secret = "${var.shared_secret}"
}

module "on-prem" {
  source = "./modules/datacenter"
  network_name = "on-prem"
  subnet_region = "us-central1"
  ip_cidr_range = "10.2.0.0/16"
  vpn_ip = "${google_compute_address.public_ip_2.address}"
  peer_ip = "${google_compute_address.public_ip_1.address}"
  destination_range = "10.1.0.0/16"
  shared_secret = "${var.shared_secret}"
}

resource "google_container_cluster" "cloud-cluster" {
  name = "cloud-cluster"
  zone = "us-west1-a"
  network = "${module.cloud.network}"
  subnetwork = "${module.cloud.subnetwork}"
  initial_node_count = 1
  min_master_version = "1.9.7-gke.0"
  node_version = "1.9.7-gke.0"
}

resource "google_container_cluster" "on-prem-cluster" {
  name = "on-prem-cluster"
  zone = "us-central1-a"
  network = "${module.on-prem.network}"
  subnetwork = "${module.on-prem.subnetwork}"
  initial_node_count = 3
  min_master_version = "1.9.7-gke.0"
  node_version = "1.9.7-gke.0"

  node_config {
    machine_type = "n1-highcpu-4"
  }

  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials on-prem-cluster --zone us-central1-a"
  }

  provisioner "local-exec" {
    command = "kubectl create -f manifests/es-discovery-svc.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl create -f manifests/es-svc.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl create -f manifests/es-master.yaml && kubectl rollout status -f manifests/es-master.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl create -f manifests/es-client.yaml && kubectl rollout status -f manifests/es-client.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl create -f manifests/es-data-svc.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl create -f manifests/es-data-stateful.yaml && kubectl rollout status -f manifests/es-data-stateful.yaml"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "kubectl delete -f manifests/es-data-stateful.yaml"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "kubectl delete -f manifests/es-data-svc.yaml"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "kubectl delete -f manifests/es-client.yaml"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "kubectl delete -f manifests/es-master.yaml"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "kubectl delete -f manifests/es-svc.yaml"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "kubectl delete -f manifests/es-discovery-svc.yaml"
  }

}
