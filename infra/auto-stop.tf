# A build of action cache hits barely moves the farm's CPU, but the farm sends
# the outputs back, so the alarms watch the bytes each instance sends.

locals {
  idle_stops = {
    for name, stop in {
      farm = {
        name             = var.farm_name
        instance_id      = aws_instance.farm.id
        minutes          = var.farm_idle_stop_minutes
        bytes_per_second = 500
        tags             = local.farm_tags
      }
      client = {
        name        = var.client_name
        instance_id = aws_instance.client.id
        minutes     = var.client_idle_stop_minutes
        # The client sends little even while its builds run on the farm.
        bytes_per_second = 150
        tags             = {}
      }
    } : name => stop if stop.minutes > 0
  }
}

resource "aws_cloudwatch_metric_alarm" "idle_stop" {
  for_each = local.idle_stops

  alarm_name        = "${each.value.name}-idle-stop"
  alarm_description = "Stop after ${each.value.minutes} minutes sending less than ${each.value.bytes_per_second} bytes per second"
  namespace         = "AWS/EC2"
  metric_name       = "NetworkOut"
  statistic         = "Sum"

  dimensions = {
    InstanceId = each.value.instance_id
  }

  # Basic EC2 monitoring reports one datapoint every five minutes, the bytes
  # sent during it.
  period              = 300
  evaluation_periods  = each.value.minutes / 5
  datapoints_to_alarm = each.value.minutes / 5
  comparison_operator = "LessThanThreshold"
  threshold           = each.value.bytes_per_second * 300

  # Once too few real datapoints remain in the window, the missing ones count
  # as busy. A gap in reporting then doesn't stop an instance, and the alarm of
  # a stopped instance returns to OK.
  treat_missing_data = "notBreaching"
  alarm_actions      = ["arn:${data.aws_partition.current.partition}:automate:${var.aws_region}:ec2:stop"]

  tags = each.value.tags
}
