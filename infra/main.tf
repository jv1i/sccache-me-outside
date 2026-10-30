locals {
  common_tags = {
    ManagedBy = "reapi-dev-infra"
    Project   = "sccache-reapi"
  }

  client_configuration = templatefile("${path.module}/client-configure.sh.tftpl", {
    farm_private_ip = aws_instance.farm.private_ip
    flake_nix_b64   = base64encode(file("${path.module}/../client/flake.nix"))
    flake_lock_b64  = base64encode(file("${path.module}/../client/flake.lock"))
  })
  client_configuration_hash = sha256(local.client_configuration)

  client_user_data = <<-EOT
    ${local.client_configuration}
    install -d -m 0755 /var/lib/reapi-client
    printf '%s\n' '${local.client_configuration_hash}' > /var/lib/reapi-client/configuration.sha256
  EOT

  client_ssm_runner = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    cloud-init status --wait || true
    current_hash="$(cat /var/lib/reapi-client/configuration.sha256 2>/dev/null || true)"
    if [ "$current_hash" = '${local.client_configuration_hash}' ]; then
      echo 'Client configuration is already current'
      exit 0
    fi
    echo '${base64encode(local.client_configuration)}' | base64 -d | bash
    install -d -m 0755 /var/lib/reapi-client
    printf '%s\n' '${local.client_configuration_hash}' > /var/lib/reapi-client/configuration.sha256
  EOT
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_ssm_parameter" "amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "client" {
  name        = "${var.client_name}-sg"
  description = "REAPI Linux client: no inbound network access"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.client_name}-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "client_all" {
  security_group_id = aws_security_group.client.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "farm_from_client" {
  security_group_id            = aws_security_group.farm.id
  referenced_security_group_id = aws_security_group.client.id
  ip_protocol                  = "tcp"
  from_port                    = 50051
  to_port                      = 50051
  description                  = "REAPI from ${var.client_name}"

  tags = {
    Name = "${var.client_name}-to-${var.farm_name}"
  }
}

resource "aws_iam_role" "client_ssm" {
  name = "${var.client_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "client_ssm" {
  role       = aws_iam_role.client_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "client" {
  name = "${var.client_name}-profile"
  role = aws_iam_role.client_ssm.name
}

resource "aws_instance" "client" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.client_instance_type
  subnet_id              = aws_instance.farm.subnet_id
  vpc_security_group_ids = [aws_security_group.client.id]
  iam_instance_profile   = aws_iam_instance_profile.client.name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.client_volume_gb
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.client_name}-root"
    }
  }

  user_data = local.client_user_data

  # User data bootstraps new clients. The SSM association below delivers later
  # changes to the pinned environment without replacing the instance.
  user_data_replace_on_change = false

  tags = {
    Name = var.client_name
  }

  # Canonical updates the public SSM parameter regularly. Keep an existing
  # client stable; recreate deliberately when you want a newer base AMI. SSM
  # owns subsequent development-environment updates.
  lifecycle {
    # key_name is ignored only to avoid replacing clients created before SSH
    # was removed. Fresh clients are provisioned without an EC2 key pair.
    ignore_changes = [ami, key_name, user_data]
  }

  depends_on = [aws_iam_role_policy_attachment.client_ssm]
}

resource "aws_ssm_document" "client_configuration" {
  name            = "${var.client_name}-configure"
  document_type   = "Command"
  document_format = "JSON"
  target_type     = "/AWS::EC2::Instance"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Apply the OpenTofu-managed REAPI client environment"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "configureClient"
      inputs = {
        runCommand = [
          "echo '${base64encode(local.client_ssm_runner)}' | base64 -d | bash",
        ]
      }
    }]
  })

  tags = {
    Name = "${var.client_name}-configure"
  }
}

resource "aws_ssm_association" "client_configuration" {
  name             = aws_ssm_document.client_configuration.name
  association_name = "${var.client_name}-configuration"
  document_version = aws_ssm_document.client_configuration.latest_version

  targets {
    key    = "InstanceIds"
    values = [aws_instance.client.id]
  }

  tags = {
    Name = "${var.client_name}-configuration"
  }
}
