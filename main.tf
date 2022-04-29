data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Shield Custom AWS Config Rule Lambda Function
resource "aws_lambda_function" "shield_custom_aws_config_rule" {
  function_name    = "shield-custom-aws-config-rule"
  role             = aws_iam_role.shield_custom_aws_config_rule_lambda_role.arn
  runtime          = "nodejs14.x"
  handler          = "index.handler"
  filename         = "${path.module}/files/lambda-functions/zip/shield-custom-aws-config-rule.zip"
  source_code_hash = filebase64sha256("${path.module}/files/lambda-functions/zip/shield-custom-aws-config-rule.zip")
  tags = {
    stack = "Infrastructure"
  }
}

resource "aws_lambda_permission" "shield_custom_aws_config_rule_lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.shield_custom_aws_config_rule.arn
  principal     = "config.amazonaws.com"
  statement_id  = "AllowExecutionFromConfig"
}

data "aws_iam_policy_document" "shield_custom_aws_config_rule_lambda_role_policy" {
  statement {
    actions = [
      "config:Put*",
      "config:Get*",
      "config:List*",
      "config:Describe*",
      "config:BatchGet*",
      "config:Select*"
    ]
    resources = [
      "*",
    ]
  }

  statement {
    actions = [
      "shield:ListTagsForResource"
    ]
    resources = [
      "*",
    ]
  }

  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::*/AWSLogs/*/Config/*",
    ]
  }

  statement {
    actions = [
      "logs:CreateLogGroup"
    ]
    resources = [
      "arn:aws:logs:*:*",
    ]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/shield-custom-aws-config-rule:*",
    ]
  }
}

data "aws_iam_policy_document" "shield_custom_aws_config_rule_lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "shield_custom_aws_config_rule_lambda_role_policy" {
  name   = "shield-custom-aws-config-rule-lambda-role-policy"
  policy = data.aws_iam_policy_document.shield_custom_aws_config_rule_lambda_role_policy.json

  tags = {
    stack = "Infrastructure"
  }
}

resource "aws_iam_role" "shield_custom_aws_config_rule_lambda_role" {
  name               = "shield-custom-aws-config-rule-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.shield_custom_aws_config_rule_lambda_assume_role_policy.json
  tags = {
    stack = "Infrastructure"
  }
}

resource "aws_iam_policy_attachment" "shield_custom_aws_config_rule_lambda_role_policy" {
  name       = "shield-custom-aws-config-rule-lambda-role-policy-attachment"
  roles      = [aws_iam_role.shield_custom_aws_config_rule_lambda_role.name]
  policy_arn = aws_iam_policy.shield_custom_aws_config_rule_lambda_role_policy.arn
}

# Shield Custom AWS Config Rule Remediation Lambda Function
resource "aws_lambda_function" "shield_custom_aws_config_remediation" {
  function_name    = "shield-custom-aws-config-remediation"
  role             = aws_iam_role.shield_custom_aws_config_remediation_lambda_role.arn
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  timeout          = 60
  filename         = "${path.module}/files/lambda-functions/zip/shield-custom-aws-config-remediation.zip"
  source_code_hash = filebase64sha256("${path.module}/files/lambda-functions/zip/shield-custom-aws-config-remediation.zip")
  tags = {
    stack = "Infrastructure"
  }
}

data "aws_iam_policy_document" "shield_custom_aws_config_remediation_lambda_role_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup"
    ]
    resources = [
      "arn:aws:logs:*:*",
    ]
  }

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/shield-custom-aws-config-rule:*",
    ]
  }

  statement {
    actions = [
      "shield:DescribeProtection",
      "shield:EnableApplicationLayerAutomaticResponse",
      "iam:GetRole",
      "cloudfront:GetDistribution"
    ]
    resources = [
      "*",
    ]
  }
}

data "aws_iam_policy_document" "shield_custom_aws_config_remediation_lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "shield_custom_aws_config_remediation_lambda_role_policy" {
  name   = "shield-custom-aws-config-remediation-lambda-role-policy"
  policy = data.aws_iam_policy_document.shield_custom_aws_config_remediation_lambda_role_policy.json

  tags = {
    stack = "Infrastructure"
  }
}

resource "aws_iam_role" "shield_custom_aws_config_remediation_lambda_role" {
  name               = "shield-custom-aws-config-remediation-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.shield_custom_aws_config_remediation_lambda_assume_role_policy.json
  tags = {
    stack = "Infrastructure"
  }
}

resource "aws_iam_policy_attachment" "shield_custom_aws_config_remediation_lambda_role_policy" {
  name       = "shield-custom-aws-config-remediation-lambda-role-policy-attachment"
  roles      = [aws_iam_role.shield_custom_aws_config_remediation_lambda_role.name]
  policy_arn = aws_iam_policy.shield_custom_aws_config_remediation_lambda_role_policy.arn
}


# Shield Custom AWS Config Rule resources
resource "aws_config_config_rule" "shield_automitigation_enabled" {
  name        = "shield-automitigation-enabled"
  description = "The config rule checks if Automatic application layer DDoS mitigation is enabled"

  input_parameters = jsonencode(
    {
      ApplicationLayerAutomaticResponseConfiguration = "ENABLED"
    }
  )

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = aws_lambda_function.shield_custom_aws_config_rule.arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
    source_detail {
      event_source = "aws.config"
      message_type = "OversizedConfigurationItemChangeNotification"
    }
  }

  scope {
    compliance_resource_types = ["AWS::Shield::Protection"]
  }
}

# Shield Custom AWS Config Rule Remediation resources
resource "aws_config_remediation_configuration" "shield_automitigation_enabled_remediation" {
  config_rule_name = aws_config_config_rule.shield_automitigation_enabled.name
  target_type      = "SSM_DOCUMENT"
  target_id        = "shield-automitigation-enabled-remediation"

  parameter {
    name           = "ResourceID"
    resource_value = "RESOURCE_ID"
  }

  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.shield_automitigation_enabled_remediation_role.arn
  }


  automatic                  = true
  maximum_automatic_attempts = 5
  retry_attempt_seconds      = 60

  execution_controls {
    ssm_controls {
      concurrent_execution_rate_percentage = 10
      error_percentage                     = 50
    }
  }
  depends_on = [
    aws_ssm_document.shield_automitigation_enabled_remediation,
    aws_iam_role.shield_automitigation_enabled_remediation_role
  ]
}


## SSM Document for Remediation
resource "aws_ssm_document" "shield_automitigation_enabled_remediation" {
  name            = "shield-automitigation-enabled-remediation"
  document_type   = "Automation"
  document_format = "YAML"

  content = <<DOC
description: 'SSM Document which remediates the Shield Custom Config rule by invoking a lambda to set the Automatic application layer DDoS mitigation status of the Shied resource to enabled. '
schemaVersion: '0.3'
assumeRole: '${aws_iam_role.shield_automitigation_enabled_remediation_role.arn}'
parameters:
  ResourceID:
    type: String
    description: Resource ID of the shield protection.
  AutomationAssumeRole:
    type: String
    description: Assume Role used to perform redemediation.
mainSteps:
  - name: shield_automitigation_enabled_remediation
    action: 'aws:invokeLambdaFunction'
    inputs:
      InvocationType: RequestResponse
      FunctionName: '${aws_lambda_function.shield_custom_aws_config_remediation.arn}'
      InputPayload:
          ResourceID: '{{ResourceID}}'
DOC

  depends_on = [
    aws_iam_role.shield_automitigation_enabled_remediation_role
  ]
}

data "aws_iam_policy_document" "shield_automitigation_enabled_remediation_role_policy" {
  statement {
    sid = "ShieldAutomitigationEnabledRemediationRolePolicy"

    actions = [
      "lambda:InvokeFunction"
    ]

    effect = "Allow"

    resources = [
      "${aws_lambda_function.shield_custom_aws_config_remediation.arn}",
    ]
  }
}

resource "aws_iam_policy" "shield_automitigation_enabled_remediation_role_policy" {
  name   = "shield-automitigation-enabled-remediation-role-policy"
  policy = data.aws_iam_policy_document.shield_automitigation_enabled_remediation_role_policy.json

  tags = {
    stack = "Infrastructure"
  }
}

data "aws_iam_policy_document" "shield_automitigation_enabled_remediation_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "shield_automitigation_enabled_remediation_role" {
  name               = "shield-automitigation-enabled-remediation-role"
  assume_role_policy = data.aws_iam_policy_document.shield_automitigation_enabled_remediation_assume_role_policy.json
  tags = {
    stack = "Infrastructure"
  }
}

resource "aws_iam_policy_attachment" "shield_automitigation_enabled_remediation_role_policy" {
  name       = "shield-automitigation-enabled-remediation-role-policy-attachment"
  roles      = [aws_iam_role.shield_automitigation_enabled_remediation_role.name]
  policy_arn = aws_iam_policy.shield_automitigation_enabled_remediation_role_policy.arn
}
