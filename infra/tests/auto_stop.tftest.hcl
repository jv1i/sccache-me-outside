# Plans and applies against a mocked AWS provider, so no AWS account is used.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  # The provider validates ARNs and document versions even when mocked.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }

  mock_resource "aws_ssm_document" {
    defaults = {
      latest_version = "1"
    }
  }
}

override_resource {
  target = aws_instance.farm
  values = {
    id  = "i-0000000000000farm"
    arn = "arn:aws:ec2:us-east-1:123456789012:instance/i-0000000000000farm"
  }
}

override_resource {
  target = aws_instance.client
  values = {
    id  = "i-00000000000client"
    arn = "arn:aws:ec2:us-east-1:123456789012:instance/i-00000000000client"
  }
}

# The owner's terraform.tfvars is loaded too, so the runs set every value they
# check. A region other than the default checks that the stop action uses it.
variables {
  aws_region               = "eu-west-1"
  farm_idle_stop_minutes   = 60
  client_idle_stop_minutes = 180
}

run "an_idle_farm_stops_after_an_hour" {
  assert {
    condition = (
      aws_cloudwatch_metric_alarm.idle_stop["farm"].namespace == "AWS/EC2" &&
      aws_cloudwatch_metric_alarm.idle_stop["farm"].metric_name == "NetworkOut" &&
      aws_cloudwatch_metric_alarm.idle_stop["farm"].statistic == "Sum"
    )
    error_message = "The farm's idle alarm doesn't sum the bytes the farm sends, so a build of cache hits, which barely uses its CPU, can look idle."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.idle_stop["farm"].dimensions == tomap({ InstanceId = "i-0000000000000farm" })
    error_message = "The farm's idle alarm doesn't watch exactly the farm instance, which EC2 stop actions require."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.idle_stop["farm"].period * aws_cloudwatch_metric_alarm.idle_stop["farm"].evaluation_periods == 3600
    error_message = "The farm's idle alarm doesn't cover 60 minutes."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.idle_stop["farm"].datapoints_to_alarm == aws_cloudwatch_metric_alarm.idle_stop["farm"].evaluation_periods
    error_message = "The farm stops before every datapoint in its window is idle."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.idle_stop["farm"].comparison_operator == "LessThanThreshold" && aws_cloudwatch_metric_alarm.idle_stop["farm"].threshold == 150000
    error_message = "The farm's idle alarm doesn't fire below 500 bytes per second, 150000 bytes per five-minute datapoint."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.idle_stop["farm"].treat_missing_data == "notBreaching"
    error_message = "The farm's idle alarm doesn't count missing datapoints as busy, so a stopped farm's alarm may not return to OK."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.idle_stop["farm"].alarm_actions == toset(["arn:aws:automate:eu-west-1:ec2:stop"])
    error_message = "The farm's idle alarm does something other than stop the instance in its region."
  }
}

run "an_idle_client_stops_after_three_hours" {
  assert {
    condition     = aws_cloudwatch_metric_alarm.idle_stop["client"].dimensions == tomap({ InstanceId = "i-00000000000client" })
    error_message = "The client's idle alarm doesn't watch the client instance."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.idle_stop["client"].evaluation_periods == 36 && aws_cloudwatch_metric_alarm.idle_stop["client"].datapoints_to_alarm == 36
    error_message = "The client's idle alarm doesn't take 36 five-minute datapoints for 180 minutes."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.idle_stop["client"].threshold == 45000
    error_message = "The client's idle alarm doesn't fire below 150 bytes per second, 45000 bytes per five-minute datapoint."
  }
}

run "the_farm_idle_stop_can_be_disabled_alone" {
  variables {
    farm_idle_stop_minutes = 0
  }

  assert {
    condition     = keys(aws_cloudwatch_metric_alarm.idle_stop) == ["client"]
    error_message = "farm_idle_stop_minutes = 0 doesn't remove only the farm's idle alarm."
  }
}

run "an_idle_time_between_datapoints_is_refused" {
  command = plan

  variables {
    farm_idle_stop_minutes = 62
  }

  expect_failures = [var.farm_idle_stop_minutes]
}

run "an_idle_time_longer_than_a_day_is_refused" {
  command = plan

  variables {
    client_idle_stop_minutes = 1445
  }

  expect_failures = [var.client_idle_stop_minutes]
}
