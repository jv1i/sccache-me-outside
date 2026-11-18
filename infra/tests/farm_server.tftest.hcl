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

# The owner's terraform.tfvars is loaded too, so the runs set every value they
# check.
variables {
  farm_server    = "nativelink"
  nativelink_tag = "v1.4.0"
  farm_volume_gb = 30
}

# Runs first: the farm keeps its user data after it exists, and later runs
# reuse this farm.
run "a_new_farm_boots_with_the_chosen_server" {
  variables {
    farm_server = "buildbarn"
  }

  assert {
    condition     = strcontains(aws_instance.farm.user_data, "ghcr.io/buildbarn/bb-storage:")
    error_message = "A new farm's user data doesn't set up Buildbarn, so a farm created with farm_server = \"buildbarn\" starts the wrong server."
  }
}

run "the_farm_can_run_nativelink" {
  assert {
    condition     = strcontains(local.farm_configuration, "ghcr.io/tracemachina/nativelink:v1.4.0")
    error_message = "The NativeLink script doesn't use the image that nativelink_tag pins."
  }

  assert {
    condition     = !strcontains(local.farm_configuration, "ghcr.io/buildbarn/")
    error_message = "The NativeLink configuration starts Buildbarn too."
  }

  assert {
    condition     = strcontains(local.farm_configuration, "docker rm -f nativelink bb-storage")
    error_message = "The NativeLink script doesn't remove Buildbarn's containers, which hold port 50051, so NativeLink can't start after a switch."
  }
}

run "the_farm_can_run_buildbarn" {
  variables {
    farm_server = "buildbarn"
  }

  assert {
    condition = alltrue([
      for image in ["bb-storage", "bb-scheduler", "bb-worker", "bb-runner-installer"] :
      strcontains(local.farm_configuration, "ghcr.io/buildbarn/${image}:")
    ])
    error_message = "The Buildbarn script doesn't start every Buildbarn component."
  }

  assert {
    condition     = strcontains(local.farm_configuration, "-p 0.0.0.0:50051:8980")
    error_message = "bb_storage isn't published on port 50051, the only port the security group opens to the client."
  }

  assert {
    condition     = strcontains(local.farm_configuration, "docker rm -f nativelink bb-storage")
    error_message = "The Buildbarn script doesn't remove NativeLink's container, which holds port 50051, so Buildbarn can't start after a switch."
  }

  assert {
    condition     = !strcontains(local.farm_configuration, "tracemachina")
    error_message = "The Buildbarn configuration starts NativeLink too."
  }
}

run "buildbarn_keeps_its_cache_across_restarts" {
  variables {
    farm_server = "buildbarn"
  }

  assert {
    condition     = strcontains(local.farm_configuration, "stateDirectoryPath: dir + '/persistent_state'")
    error_message = "bb_storage has no persistent state, so it empties its cache on every restart."
  }

  assert {
    condition     = strcontains(local.farm_configuration, "docker stop -t 60 bb-storage")
    error_message = "The Buildbarn script removes its containers without stopping them, so bb_storage loses unsaved cache entries."
  }
}

run "switching_to_nativelink_stops_buildbarn_cleanly" {
  assert {
    condition     = strcontains(local.farm_configuration, "docker stop -t 60 bb-storage")
    error_message = "The NativeLink script removes Buildbarn without stopping it, so bb_storage loses unsaved cache entries."
  }
}

run "an_existing_farm_switches_through_ssm" {
  variables {
    farm_server = "buildbarn"
  }

  assert {
    condition     = strcontains(aws_ssm_document.farm_configuration.content, base64encode(local.farm_ssm_runner))
    error_message = "The SSM document doesn't run the runner script, so a running farm never gets configuration changes."
  }

  assert {
    condition = (
      strcontains(local.farm_ssm_runner, base64encode(local.farm_configuration)) &&
      strcontains(local.farm_ssm_runner, sha256(local.farm_configuration))
    )
    error_message = "The runner doesn't apply Buildbarn's configuration or compare its hash, so a running farm doesn't switch."
  }
}

run "an_unknown_server_is_refused" {
  command = plan

  variables {
    farm_server = "buildgrid"
  }

  expect_failures = [var.farm_server]
}

run "buildbarn_on_a_small_volume_is_refused" {
  command = plan

  variables {
    farm_server    = "buildbarn"
    farm_volume_gb = 20
  }

  expect_failures = [aws_instance.farm]
}

# Fails if the volume precondition fires.
run "nativelink_on_a_small_volume_is_allowed" {
  command = plan

  variables {
    farm_volume_gb = 20
  }
}
