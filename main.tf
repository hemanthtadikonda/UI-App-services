resource "aws_security_group" "main" {
  name        = "${local.name_prefix}-sg"
  description = "${local.name_prefix}-sg"
  vpc_id      = var.vpc_id
  tags        = merge( local.tags ,{ Name = "${local.name_prefix}-sg" } )

  ingress  {
    description      = "APP"
    from_port        = var.app_port
    to_port          = var.app_port
    protocol         = "tcp"
    cidr_blocks      = var.sg_ingress_cidr_blocks
  }
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.default_vpc_cidr_block
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_lb_target_group" "main" {
  name     = "${local.name_prefix}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  tags        = merge ( local.tags ,{ Name = "${local.name_prefix}-tg" } )

  health_check = {
    enabled = true
    healthy_threshold = 2
    interval = 10
    matcher = 200
    path = var.health_check_path
    port = var.app_port
    timeout = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "public" {
  count      = var.service == "frontend" ? 1 : 0
  name        = "${var.env}-${var.service}-pub_lb_tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.default_vpc_id
  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 5
    path                = "/"
    port                = var.app_port
    timeout             = 2
    unhealthy_threshold = 2
    matcher             = "404"
  }
}

resource "aws_lb_target_group_attachment" "main" {
  count            = var.service == "frontend" ? length(var.az) : 0
  target_group_arn = aws_lb_target_group.public[0].arn
  target_id        = element(tolist(data.dns_a_record_set.private_lb_add.addrs), count.index )
  port             = 80
  availability_zone = "all"
}
resource "aws_route53_record" "main" {
  zone_id = var.hosted_zone_id
  name    = "${var.service}-${var.env}"
  type    = "CNAME"
  ttl     = 30
  records = [ var.service == "frontend" ? var.public_lb_dns_name : var.private_lb_dns_name ]
}

resource "aws_lb_listener_rule" "main" {
  listener_arn = var.private_lb_listener_arn
  priority     = var.lb_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = ["${var.service}-${var.env}.tadikonda.site"]
    }
  }
}
resource "aws_lb_listener_rule" "public" {
  count = var.service == "frontend" ? 1 : 0
  listener_arn = var.public_alb_listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public[0].arn
  }

  condition {
    host_header {
      values = ["${var.service}-${var.env}.tadikonda.site"]
    }
  }
}

resource "aws_launch_template" "main" {
  name                   = "${local.name_prefix}-template"
  image_id               =  var.ami_id
  key_name               =  var.key_name
  instance_type          = var.instance_type
  vpc_security_group_ids = [ aws_security_group.main.id ]
  iam_instance_profile {
    name = "${local.name_prefix}-role-profile"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags,{ Name = "${local.name_prefix}-tem" })
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh",{ component = var.service,env = var.env }))
}
resource "aws_autoscaling_group" "main" {
  name_prefix         = "${local.name_prefix}-asg"
  vpc_zone_identifier = var.app_subnet_ids
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  min_size            = var.min_size
  target_group_arns   = [ aws_lb_target_group.main.arn ]

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = local.name_prefix
    propagate_at_launch = true
  }
  tag {
    key                 = "Monitor"
    value               = "yes"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "main" {
  autoscaling_group_name = aws_autoscaling_group.main.name
  name                   = "${aws_autoscaling_group.main.name}-policy"
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 40.0
  }
}