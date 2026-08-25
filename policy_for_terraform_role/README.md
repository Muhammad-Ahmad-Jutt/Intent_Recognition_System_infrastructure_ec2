# Terraform AWS IAM Policies

These policy files grant the Terraform identity permission to manage the AWS resources used by this project:

- `create-delete-ec2.json`: create and delete EC2 networking, instances, and key pairs
- `terraform-s3.json`: create and manage the Terraform S3 bucket configuration
- `ecr-terraform-policy _ IAM _ Global.json`: create and manage the ECR repository
- `terrform-crud-secret-manager.json`: create and manage Secrets Manager secrets
- `terraform-role.json`: create and manage IAM roles and instance profiles required by Terraform

Review these permissions with your AWS administrator before using them. The IAM policy is deliberately broad in places so Terraform can create and destroy infrastructure; use resource-specific ARNs and fewer actions for production where practical.

## Before uploading the policies

The policy files currently contain placeholder `Resource` values such as `arn of the resources`. These are not valid JSON or valid IAM policies. Replace every placeholder with an appropriate ARN. For a quick working setup, use:

```json
"Resource": "*"
```

The EC2 policy also contains the invalid line `//arn of the resources`; remove the comment and set the value to `"*"`.

For a safer setup, replace `"*"` with the ARNs of the specific buckets, repositories, secrets, roles, and instance profiles that Terraform manages. Some `Describe*` actions and IAM actions may still require `"*"` because AWS does not support resource-level permissions for them.

Validate each file after editing.

PowerShell:

```powershell
Get-ChildItem -Filter *.json | ForEach-Object {
  Get-Content $_.FullName -Raw | ConvertFrom-Json | Out-Null
  Write-Host "Valid: $($_.Name)"
}
```

AWS CLI validation:

```powershell
Get-ChildItem -Filter *.json | ForEach-Object {
  aws iam simulate-custom-policy --policy-input-list (Get-Content $_.FullName -Raw) --action-names sts:GetCallerIdentity | Out-Null
}
```

## AWS Console: attach policies to a Terraform IAM user

Use this when Terraform authenticates with an IAM user such as `terraform`.

1. Open **IAM** in the correct AWS account and region-independent IAM console.
2. Select **Policies**, then **Create policy**.
3. Choose the **JSON** tab and paste the contents of one corrected JSON file.
4. Select **Next**, name the policy to match its purpose, and create it.
5. Repeat for all five JSON files.
6. Open **Users**, select the Terraform user, and choose **Add permissions**.
7. Choose **Attach policies directly**, select the five customer-managed policies, and add permissions.
8. Confirm the user has active access keys, then configure Terraform with that access key through environment variables or your normal AWS credentials profile.

Recommended policy names:

- `TerraformCreateDeleteEC2`
- `TerraformS3`
- `TerraformECR`
- `TerraformSecretsManager`
- `TerraformIAMRoleManagement`

Do not put long-lived access keys in `terraform.tfvars`, `example.env`, source control, or the Docker image.

## AWS Console: use a Terraform IAM role

For CI/CD or federation, prefer a role instead of an IAM user:

1. Open **IAM > Policies** and create the five customer-managed policies as described above.
2. Open **IAM > Roles > Create role**.
3. Choose the trusted principal used by Terraform, such as GitHub Actions OIDC, another AWS account, or an administrative bootstrap user.
4. Name the role, for example `terraform-role`.
5. Attach the five policies to the role and create it.
6. Configure the Terraform runner to assume this role and set the role ARN in its AWS provider or CI/CD configuration.

`terraform-role.json` grants permissions to manage IAM roles and includes `iam:PassRole`. Restrict `iam:PassRole` to only the roles Terraform must pass whenever possible.

## AWS CLI: create and attach customer-managed policies to a user

Run these commands from this directory after correcting and validating the JSON files. Replace `terraform` and the account/profile values as needed.

```powershell
$PolicyPath = (Get-Location).Path
$UserName = "terraform"
$Prefix = "Terraform"

$Policies = @(
  @{ Name = "${Prefix}CreateDeleteEC2"; File = "create-delete-ec2.json" },
  @{ Name = "${Prefix}S3"; File = "terraform-s3.json" },
  @{ Name = "${Prefix}ECR"; File = "ecr-terraform-policy _ IAM _ Global.json" },
  @{ Name = "${Prefix}SecretsManager"; File = "terrform-crud-secret-manager.json" },
  @{ Name = "${Prefix}IAMRoleManagement"; File = "terraform-role.json" }
)

foreach ($Policy in $Policies) {
  $Arn = aws iam create-policy `
    --policy-name $Policy.Name `
    --policy-document (Get-Content (Join-Path $PolicyPath $Policy.File) -Raw) `
    --query 'Policy.Arn' --output text

  aws iam attach-user-policy --user-name $UserName --policy-arn $Arn
}
```

If the policies already exist, skip `create-policy` and attach them using their ARNs:

```powershell
$AccountId = aws sts get-caller-identity --query Account --output text
$UserName = "terraform"
$PolicyNames = @(
  "TerraformCreateDeleteEC2",
  "TerraformS3",
  "TerraformECR",
  "TerraformSecretsManager",
  "TerraformIAMRoleManagement"
)

foreach ($PolicyName in $PolicyNames) {
  aws iam attach-user-policy `
    --user-name $UserName `
    --policy-arn "arn:aws:iam::${AccountId}:policy/$PolicyName"
}
```

## AWS CLI: create a role and attach the policies

Create a trust policy appropriate for the Terraform runner. This example trusts an existing IAM user; replace the account and user ARN before use.

```powershell
@'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::ACCOUNT_ID:user/terraform"},
    "Action": "sts:AssumeRole"
  }]
}
'@ | Set-Content trust-policy.json

aws iam create-role `
  --role-name terraform-role `
  --assume-role-policy-document file://trust-policy.json
```

After creating the five customer-managed policies, attach them to the role:

```powershell
$AccountId = aws sts get-caller-identity --query Account --output text
$RoleName = "terraform-role"
$PolicyNames = @(
  "TerraformCreateDeleteEC2",
  "TerraformS3",
  "TerraformECR",
  "TerraformSecretsManager",
  "TerraformIAMRoleManagement"
)

foreach ($PolicyName in $PolicyNames) {
  aws iam attach-role-policy `
    --role-name $RoleName `
    --policy-arn "arn:aws:iam::${AccountId}:policy/$PolicyName"
}
```

Verify the attachments:

```powershell
aws iam list-attached-user-policies --user-name terraform
aws iam list-attached-role-policies --role-name terraform-role
aws sts get-caller-identity
```

## Run Terraform

Use the same AWS profile or assumed role configured for the identity above, then run Terraform from the `data` directory:

```powershell
terraform init
terraform plan -var-file=example.tfvars
terraform apply -var-file=example.tfvars
```

Ensure the selected AWS identity has access to the configured region and that the S3 bucket name is globally unique. `terraform destroy -var-file=example.tfvars` removes the resources managed by this configuration.

AI-Generated Content Notice
This file was generated by GitHub Copilot  on 25 august 2026.
This content may contain errors, inaccuracies, or incomplete information.
A human should review and verify this file before you use it for important tasks.