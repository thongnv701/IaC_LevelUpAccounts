# AWS Secrets Manager for storing GitHub token
resource "aws_secretsmanager_secret" "github_token" {
  name        = "level-up-accounts/github-token"
  description = "GitHub token for accessing private configuration repository"
  
  tags = {
    Environment = "production"
    Application = "level-up-accounts"
  }
}

resource "aws_secretsmanager_secret_version" "github_token" {
  secret_id     = aws_secretsmanager_secret.github_token.id
  secret_string = jsonencode({
    token = var.github_token
  })
}

# IAM policy for External Secrets Operator
data "aws_iam_policy_document" "external_secrets_policy" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      aws_secretsmanager_secret.github_token.arn
    ]
  }
}

resource "aws_iam_policy" "external_secrets_policy" {
  name        = "level-up-accounts-external-secrets"
  description = "Policy for External Secrets Operator to access AWS Secrets Manager"
  policy      = data.aws_iam_policy_document.external_secrets_policy.json
}

# IAM user for External Secrets Operator (K3s doesn't have built-in OIDC)
resource "aws_iam_user" "external_secrets_user" {
  name = "level-up-accounts-external-secrets"
  
  tags = {
    Environment = "production"
    Application = "level-up-accounts"
    Component   = "external-secrets"
  }
}

resource "aws_iam_user_policy_attachment" "external_secrets_policy_attachment" {
  user       = aws_iam_user.external_secrets_user.name
  policy_arn = aws_iam_policy.external_secrets_policy.arn
}

resource "aws_iam_access_key" "external_secrets_access_key" {
  user = aws_iam_user.external_secrets_user.name
}

# Store the access key in Secrets Manager for External Secrets Operator to use
resource "aws_secretsmanager_secret" "external_secrets_aws_credentials" {
  name        = "level-up-accounts/external-secrets-aws-credentials"
  description = "AWS credentials for External Secrets Operator"
  
  tags = {
    Environment = "production"
    Application = "level-up-accounts"
  }
}

resource "aws_secretsmanager_secret_version" "external_secrets_aws_credentials" {
  secret_id     = aws_secretsmanager_secret.external_secrets_aws_credentials.id
  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.external_secrets_access_key.id
    secret_access_key = aws_iam_access_key.external_secrets_access_key.secret
  })
} 