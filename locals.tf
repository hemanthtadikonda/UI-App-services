locals {
  name_prefix = "${var.env}-${var.service}"
  tags        = merge( var.tags , { tf-module = "app" },{ env = var.env } )
}