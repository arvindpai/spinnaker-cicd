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

### main.tf
resource "google_compute_network" "network" {
  name                    = "${var.network_name}"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "subnetwork" {
  name          = "${var.network_name}-${var.subnet_region}"
  ip_cidr_range = "${var.primary_range}"
  network       = "${google_compute_network.network.self_link}"
  region        = "${var.subnet_region}"

  secondary_ip_range {
    range_name    = "${var.network_name}-secondary-range"
    ip_cidr_range = "${var.secondary_range}"
  }
}

resource "google_compute_vpn_gateway" "vpn_gateway" {
  name    = "${var.network_name}-vpn-gateway"
  network = "${google_compute_network.network.self_link}"
  region  = "${var.subnet_region}"
}

resource "google_compute_forwarding_rule" "esp_rule" {
  name        = "${var.network_name}-esp-rule"
  region      = "${var.subnet_region}"
  ip_protocol = "ESP"
  ip_address  = "${var.vpn_ip}"
  target      = "${google_compute_vpn_gateway.vpn_gateway.self_link}"
}

resource "google_compute_forwarding_rule" "udp_500_rule" {
  name        = "${var.network_name}-udp-500-rule"
  region      = "${var.subnet_region}"
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = "${var.vpn_ip}"
  target      = "${google_compute_vpn_gateway.vpn_gateway.self_link}"
}

resource "google_compute_forwarding_rule" "udp_4500_rule" {
  name        = "${var.network_name}-udp-4500-rule"
  region      = "${var.subnet_region}"
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = "${var.vpn_ip}"
  target      = "${google_compute_vpn_gateway.vpn_gateway.self_link}"
}

resource "google_compute_firewall" "ssh-anywhere" {
  name    = "${var.network_name}-ssh-anywhere"
  network = "${google_compute_network.network.self_link}"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_vpn_tunnel" "vpn_tunnel" {
  depends_on = [
    "google_compute_forwarding_rule.esp_rule",
    "google_compute_forwarding_rule.udp_500_rule",
    "google_compute_forwarding_rule.udp_4500_rule",
  ]

  name                    = "${var.network_name}-vpn-tunnel"
  region                  = "${var.subnet_region}"
  peer_ip                 = "${var.peer_ip}"
  shared_secret           = "${var.shared_secret}"
  target_vpn_gateway      = "${google_compute_vpn_gateway.vpn_gateway.self_link}"
  local_traffic_selector  = ["${var.primary_range}", "${var.secondary_range}"]
  remote_traffic_selector = ["${var.destination_range}"]
}

resource "google_compute_route" "route_to_vpn" {
  name                = "${var.network_name}-route-to-vpn"
  network             = "${google_compute_network.network.self_link}"
  dest_range          = "${var.destination_range}"
  priority            = 1000
  next_hop_vpn_tunnel = "${google_compute_vpn_tunnel.vpn_tunnel.self_link}"
}
