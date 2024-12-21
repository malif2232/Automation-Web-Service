# Provider Configuration
provider "aws" {
  region  = "us-east-1"
}

# Security Group for Web Servers
resource "aws_security_group" "webserver_sg" {
  name        = "webserver-security-group"
  description = "Security group for web servers"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22000
    to_port     = 22000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for Load Balancer
resource "aws_security_group" "loadbalancer_sg" {
  name        = "loadbalancer-security-group"
  description = "Security group for load balancer"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22000
    to_port     = 22000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Web Server Instances
resource "aws_instance" "webservers" {
  count                       = 3
  ami                         = "ami-0664c8f94c2a2261b"
  instance_type               = "t2.micro"
  key_name                    = "terraform"
  vpc_security_group_ids      = [aws_security_group.webserver_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "Webserver-${count.index + 1}"
  }

  user_data = <<-EOF
              #!/bin/bash
              echo "Port 22" | sudo tee -a /etc/ssh/sshd_config
              echo "Port 22000" | sudo tee -a /etc/ssh/sshd_config
              sudo systemctl restart sshd
              EOF
}

# Load Balancer Instance
resource "aws_instance" "loadbalancer" {
  ami                         = "ami-0664c8f94c2a2261b"
  instance_type               = "t2.micro"
  key_name                    = "terraform"
  vpc_security_group_ids      = [aws_security_group.loadbalancer_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "LoadBalancer"
  }

  user_data = <<-EOF
              #!/bin/bash
              echo "Port 22" | sudo tee -a /etc/ssh/sshd_config
              echo "Port 22000" | sudo tee -a /etc/ssh/sshd_config
              sudo systemctl restart sshd
              EOF
}

# Elastic IPs for Web Servers
resource "aws_eip" "webserver_eips" {
  count    = 3
  instance = aws_instance.webservers[count.index].id

  tags = {
    Name = "Webserver-${count.index + 1}-EIP"
  }
}

# Elastic IP for Load Balancer
resource "aws_eip" "loadbalancer_eip" {
  instance = aws_instance.loadbalancer.id

  tags = {
    Name = "LoadBalancer-EIP"
  }
}

# Output Elastic IPs
output "webserver_ips" {
  value = aws_eip.webserver_eips[*].public_ip
}

output "loadbalancer_ip" {
  value = aws_eip.loadbalancer_eip.public_ip
}

# Create Ansible Inventory
resource "null_resource" "create_inventory" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "[webservers]" > ../ansible/inventory.txt
      %{ for index, ip in aws_eip.webserver_eips[*].public_ip ~}
      echo "${ip} ansible_ssh_user=ubuntu ansible_ssh_private_key_file=/home/alif/Downloads/terraform.pem ansible_port=22 web_number=${index + 1}" >> ../ansible/inventory.txt
      %{ endfor ~}
      echo "[loadbalancer]" >> ../ansible/inventory.txt
      echo "${aws_eip.loadbalancer_eip.public_ip} ansible_ssh_user=ubuntu ansible_ssh_private_key_file=/home/alif/Downloads/terraform.pem ansible_port=22" >> ../ansible/inventory.txt
    EOT
  }

  depends_on = [aws_eip.webserver_eips, aws_eip.loadbalancer_eip]
}
