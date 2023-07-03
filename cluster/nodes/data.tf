data "aws_ami" "talos" {
  owners     = ["540036508848"]
  name_regex = "^talos-${var.talos_version}-${var.region}-amd64$"
}