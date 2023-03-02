data "aws_ami" "talos" {
  owners     = ["540036508848"]
  name_regex = "^talos-${var.talos_version}-us-east-1-amd64$"
}