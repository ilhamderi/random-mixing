#firewall
resource "google_compute_firewall" "firewall" {
  name    = "internal-access"
  project = "staging-351801"
  network = "playground-network"
  allow {
    protocol = "all"
  }
  source_ranges = ["172.168.0.0/24","10.184.0.0/20"]
  target_tags   = ["internal-access"]
}

#create vm instance
resource "google_compute_instance" "metabase" {
  name         = "metabase"
  project      = "staging-351801"
  machine_type = "e2-small"
  zone         = "asia-southeast2-b"
  tags         = ["internal-access","http-server"]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 15
    }
  }
  network_interface {
    network = "playground-network"
    subnetwork= "projects/staging-351801/regions/asia-southeast2/subnetworks/playground-subnet"
  }
 
  metadata_startup_script = "${file("startup.sh")}"

  metadata = {
    ssh-keys = "ilham:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDqZ1x4qGkksO48nbYCzRPTSJ4S4c3UOhwQInQlPWWgX7B+ku+1CDf8DOlSpRCS2XZ+nIrhpnJ2kKL0E0RDsoSYvyshblE0Oglvr2eYQuC36so906ZyB0hNmW8mvhkHhvNBRbR6i4qgT1NE6TVxzpQWJJVSzNds1hgpHiZkIGQXIngQtYwMzYgiRAiHSHnGqr7w3r8G31eTq/Hak5xjNhOGqT9GXiRXeVYrZPnFJR3iLevrcl7RQcfHLiFkmysg6UILlIuBWqn/fKyXBdsIMabwm0lgRCjIiB7kNvISCJsB/eMKkyfbOudLsqNZR3YVeOch0h0uIJDzjdJCRp7LmOs0ngnQRSGdkLxiqe5PqXY9tzsqLCYJkYPPuMbc/JlkglmY85uL98y1EfqHAG/cxZkFqor3qEaIMLeLvbXmlhU2S8blxgvCjdo6WkEq94kZZZ4v2m0BgXbeHvOEENGLMneIjckpW4aaesK+P3i8oDumBpC+4n8lOw7ZwBR8dvTsrn8= ilham@jump-server"
  }
}

#network group
resource "google_compute_instance_group" "metabase" {
  name        = "metabase"
  project     = "staging-351801"
  description = "Terraform metabase instance group"

  instances = [google_compute_instance.metabase.id]

  named_port {
    name = "http"
    port = "80"
  }

  zone = "asia-southeast2-b"

  depends_on = [ google_compute_instance.metabase ]
}

# health check
resource "google_compute_health_check" "hc-http" {
  name     = "health-check"
  project     = "staging-351801"
  provider = google-beta
  http_health_check {
    port = "80"
  }
}

# URL map
resource "google_compute_url_map" "url-map" {
  name            = "default-path"
  project         = "staging-351801"
  provider        = google-beta
  default_service = google_compute_backend_service.default.id
}

# backend service
resource "google_compute_backend_service" "default" {
  name                  = "bs-metabase"
  provider              = google-beta
  project               = "staging-351801"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.hc-http.id]
  backend {
    group           = google_compute_instance_group.metabase.id
    balancing_mode  = "UTILIZATION"
  }
}

#proxy
resource "google_compute_target_http_proxy" "proxy-default" {
  name        = "target-default"
  project     = "staging-351801"
  description = "proxy default"
  url_map     = google_compute_url_map.url-map.id
}

# We create a public IP address for metabase loadbalancer
resource "google_compute_global_address" "ip_static_metabase" {
  name = "metabase-address"
  project = "staging-351801"
}

# forwarding rule
resource "google_compute_global_forwarding_rule" "google_compute_forwarding_rule" {
  name                  = "metabase-loadbalancer"
  project               = "staging-351801"
  provider              = google-beta
  depends_on            = [google_compute_backend_service.default]
  ip_address            = google_compute_global_address.ip_static_metabase.id 
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.proxy-default.id
}
