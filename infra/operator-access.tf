data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "rig_operator" {
  statement {
    sid = "DiscoverRig"

    actions = [
      "ec2:DescribeInstances",
      "ssm:DescribeInstanceInformation",
      "ssm:GetCommandInvocation",
      "ssm:GetConnectionStatus",
      "ssm:GetDocument",
      "ssm:ListDocuments",
    ]

    resources = ["*"]
  }

  statement {
    sid = "StartAndStopRig"

    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances",
    ]

    resources = [
      aws_instance.farm.arn,
      aws_instance.client.arn,
    ]
  }

  statement {
    sid     = "UseSessionManager"
    actions = ["ssm:StartSession"]

    resources = [
      aws_instance.farm.arn,
      aws_instance.client.arn,
      "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:document/SSM-SessionManagerRunShell",
      "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::document/AWS-StartInteractiveCommand",
      "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::document/AWS-StartPortForwardingSession",
      "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::document/AWS-StartSSHSession",
    ]
  }

  statement {
    sid     = "UseRigChecks"
    actions = ["ssm:SendCommand"]

    resources = [
      aws_instance.farm.arn,
      aws_instance.client.arn,
      "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::document/AWS-RunShellScript",
    ]
  }

  statement {
    sid     = "SessionDataChannel"
    actions = ["ssmmessages:OpenDataChannel"]

    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:*:*:session/$${aws:userid}-*",
    ]
  }

  statement {
    sid = "ManageOwnSessions"

    actions = [
      "ssm:ResumeSession",
      "ssm:TerminateSession",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:*:*:session/$${aws:userid}-*",
    ]
  }
}

resource "aws_iam_policy" "rig_operator" {
  name        = "sccache-rig-operator"
  description = "Operate and access the existing sccache development rig without changing its infrastructure"
  policy      = data.aws_iam_policy_document.rig_operator.json
}

resource "aws_iam_group" "rig_operators" {
  name = "sccache-rig-operators"
}

resource "aws_iam_group_policy_attachment" "rig_operator" {
  group      = aws_iam_group.rig_operators.name
  policy_arn = aws_iam_policy.rig_operator.arn
}

resource "aws_iam_group_policy_attachment" "local_login" {
  group      = aws_iam_group.rig_operators.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/SignInLocalDevelopmentAccess"
}
