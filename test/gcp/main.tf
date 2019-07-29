provider "google" {
  project = "${var.project}"
  region  = "${var.region}"
  # credentials comes from env var GOOGLE_CREDENTIALS
}

resource "google_compute_instance" "aka_test" {
  name         = "${var.name}"
  machine_type = "n1-standard-2"
  zone         = "us-central1-f"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-1804-lts"
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP
    }
  }

  metadata = {
    ssh-keys = "aka:${file("/.ssh/id_rsa.pub")}"
  }

  provisioner "file" {
		source = "/dist/aka-ubuntu-1804.tar.gz"
		destination = "/home/aka/aka-ubuntu-1804.tar.gz"

    connection {
      type        = "ssh"
			host = "${google_compute_instance.aka_test.network_interface.0.access_config.0.nat_ip}"
      user        = "aka"
      private_key = "${file("/.ssh/id_rsa")}"
    }
	}

  provisioner "remote-exec" {
    inline = [
			"tar xvf aka-ubuntu-1804.tar.gz",
			"cd scripts && cat install.sh | sudo bash",
		]

    connection {
      type        = "ssh"
			host = "${google_compute_instance.aka_test.network_interface.0.access_config.0.nat_ip}"
      user        = "aka"
      private_key = "${file("/.ssh/id_rsa")}"
    }
  }
}
