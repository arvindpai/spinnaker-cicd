# Copyright 2018 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

### provision elasticsearch cluster in GKE (simulates on prem) and cloud GKE cluster
resource "google_compute_address" "public_ip_1" {
  name   = "public-ip-1"
  region = "${var.region_cloud}"
}

resource "google_compute_address" "public_ip_2" {
  name   = "public-ip-2"
  region = "${var.region_on_prem}"
}

module "cloud" {
  source            = "modules/datacenter"
  network_name      = "cloud"
  subnet_region     = "${var.region_cloud}"
  primary_range     = "${lookup(var.cloud, "primary_range")}"
  secondary_range   = "${lookup(var.cloud, "secondary_range")}"
  vpn_ip            = "${google_compute_address.public_ip_1.address}"
  peer_ip           = "${google_compute_address.public_ip_2.address}"
  destination_range = "${lookup(var.cloud, "destination_range")}"
  shared_secret     = "${var.shared_secret}"
}

module "on-prem" {
  source            = "modules/datacenter"
  network_name      = "on-prem"
  subnet_region     = "${var.region_on_prem}"
  primary_range     = "${lookup(var.on_prem, "primary_range")}"
  secondary_range   = "${lookup(var.on_prem, "secondary_range")}"
  vpn_ip            = "${google_compute_address.public_ip_2.address}"
  peer_ip           = "${google_compute_address.public_ip_1.address}"
  destination_range = "${lookup(var.on_prem, "destination_range")}"
  shared_secret     = "${var.shared_secret}"
}

resource "google_compute_firewall" "on-prem-ingress" {
  name    = "on-prem-ingress"
  network = "${module.on-prem.network}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["9200"]
  }

  source_ranges = ["${lookup(var.on_prem, "destination_range")}"]
}

data "google_container_engine_versions" "on-prem" {
  zone = "${var.zone_on_prem}"
}

resource "google_container_cluster" "on-prem-cluster" {
  name = "on-prem-cluster"
  zone = "${var.zone_on_prem}"

  additional_zones = "${var.zone_on_prem_failover}"

  network            = "${module.on-prem.network}"
  subnetwork         = "${module.on-prem.subnetwork}"
  initial_node_count = 3
  min_master_version = "${data.google_container_engine_versions.on-prem.latest_node_version}"

  ip_allocation_policy {
    cluster_secondary_range_name  = "${module.on-prem.secondary_range_name}"
    services_secondary_range_name = "${module.on-prem.secondary_range_name}"
  }

  node_config {
    machine_type = "${lookup(var.on_prem, "machine_type")}"
  }
}

data "google_container_engine_versions" "cloud" {
  zone = "${var.zone_cloud}"
}

resource "google_container_cluster" "cloud-cluster" {
  name               = "cloud-cluster"
  zone               = "${var.zone_cloud}"
  network            = "${module.cloud.network}"
  subnetwork         = "${module.cloud.subnetwork}"
  initial_node_count = 1
  min_master_version = "${data.google_container_engine_versions.cloud.latest_node_version}"

  ip_allocation_policy {
    cluster_secondary_range_name  = "${module.cloud.secondary_range_name}"
    services_secondary_range_name = "${module.cloud.secondary_range_name}"
  }
}
