data "dns_a_record_set" "private_lb_add" {
  host = var.private_lb_dns_name
}
