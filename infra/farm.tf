locals {
  farm_tags = {
    ManagedBy  = "sccache-reapi-farm"
    FarmName   = var.farm_name
    FarmRegion = var.aws_region
  }

  farm_configuration = replace(
    file("${path.module}/farm-configure.sh"),
    "__TAG__",
    var.nativelink_tag,
  )
  farm_configuration_hash = sha256(local.farm_configuration)

  # Mark a successful first-boot run so the initial SSM association does not
  # immediately repeat the same Docker build.
  farm_user_data = <<-EOT
    ${local.farm_configuration}
    install -d -m 0755 /var/lib/reapi-farm
    printf '%s\n' '${local.farm_configuration_hash}' > /var/lib/reapi-farm/configuration.sha256
  EOT

  # Associations can become active while cloud-init is still running. Wait for
  # it, then apply only when the desired configuration hash has changed.
  farm_ssm_runner = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    cloud-init status --wait || true
    current_hash="$(cat /var/lib/reapi-farm/configuration.sha256 2>/dev/null || true)"
    if [ "$current_hash" = '${local.farm_configuration_hash}' ]; then
      echo 'NativeLink configuration is already current'
      exit 0
    fi
    echo '${base64encode(local.farm_configuration)}' | base64 -d | bash
    install -d -m 0755 /var/lib/reapi-farm
    printf '%s\n' '${local.farm_configuration_hash}' > /var/lib/reapi-farm/configuration.sha256
  EOT
}

resource "aws_iam_role" "farm_ssm" {
  name = "${var.farm_name}-role"

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

  tags = local.farm_tags
}

resource "aws_iam_role_policy_attachment" "farm_ssm" {
  role       = aws_iam_role.farm_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "farm" {
  name = "${var.farm_name}-profile"
  role = aws_iam_role.farm_ssm.name
  tags = local.farm_tags
}

resource "aws_security_group" "farm" {
  name        = "${var.farm_name}-sg"
  description = "REAPI farm (no inbound rules)"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(local.farm_tags, {
    Name = "${var.farm_name}-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "farm_all" {
  security_group_id = aws_security_group.farm.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${var.farm_name}-all-egress"
  }
}

resource "aws_instance" "farm" {
  ami                    = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type          = var.farm_instance_type
  vpc_security_group_ids = [aws_security_group.farm.id]
  iam_instance_profile   = aws_iam_instance_profile.farm.name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.farm_volume_gb
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.farm_tags, {
      Name = "${var.farm_name}-root"
    })
  }

  user_data = local.farm_user_data

  # User data bootstraps new instances. Later configuration changes are applied
  # by the SSM association below, without modifying or restarting EC2.
  user_data_replace_on_change = false

  tags = merge(local.farm_tags, {
    Name = var.farm_name
  })

  # Amazon Linux updates its public SSM parameter regularly. Recreate the farm
  # deliberately when a newer base AMI is wanted. User data is creation-only;
  # SSM owns subsequent NativeLink configuration updates.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [aws_iam_role_policy_attachment.farm_ssm]
}

resource "aws_ssm_document" "farm_configuration" {
  name            = "${var.farm_name}-configure"
  document_type   = "Command"
  document_format = "JSON"
  target_type     = "/AWS::EC2::Instance"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Apply the OpenTofu-managed NativeLink farm configuration"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "configureNativeLink"
      inputs = {
        runCommand = [
          "echo '${base64encode(local.farm_ssm_runner)}' | base64 -d | bash",
        ]
      }
    }]
  })

  tags = local.farm_tags
}

resource "aws_ssm_association" "farm_configuration" {
  name             = aws_ssm_document.farm_configuration.name
  association_name = "${var.farm_name}-configuration"
  document_version = aws_ssm_document.farm_configuration.latest_version

  targets {
    key    = "InstanceIds"
    values = [aws_instance.farm.id]
  }

  tags = local.farm_tags
}
