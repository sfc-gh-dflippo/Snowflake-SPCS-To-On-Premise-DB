# AWS Infrastructure for Snowflake PrivateLink to On-Premise Database

# --- 1. Network Load Balancer (NLB) ---
resource "aws_lb" "snowflake_onprem_nlb" {
  name_prefix        = "sf-op-"
  internal           = true
  load_balancer_type = "network"
  subnets            = [var.subnet_id_1, var.subnet_id_2]

  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false

  tags = {
    Name = "Snowflake-OnPrem-NLB"
  }
}

resource "aws_lb_target_group" "snowflake_onprem_target_group" {
  name        = "snowflake-onprem-tg"
  port        = var.database_port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name = "Snowflake-OnPrem-TG"
  }
}

resource "aws_lb_target_group_attachment" "onprem_db" {
  target_group_arn = aws_lb_target_group.snowflake_onprem_target_group.arn
  target_id        = var.on_prem_database_ip
  port             = var.database_port
}

resource "aws_lb_listener" "snowflake_onprem_listener" {
  load_balancer_arn = aws_lb.snowflake_onprem_nlb.arn
  port              = var.database_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.snowflake_onprem_target_group.arn
  }
}

# --- 2. VPC Endpoint Service ---
resource "aws_vpc_endpoint_service" "snowflake_vpc_endpoint_service" {
  acceptance_required        = true
  network_load_balancer_arns = [aws_lb.snowflake_onprem_nlb.arn]

  tags = {
    Name = "Snowflake-OnPrem-VPC-Endpoint-Service"
  }
}

# --- 3. Route 53 Resolver (Hybrid DNS) ---
resource "aws_route53_resolver_endpoint" "onprem_resolver_endpoint" {
  name      = "onprem-outbound-resolver"
  direction = "OUTBOUND"

  security_group_ids = [
    aws_security_group.dns_resolver_sg.id
  ]

  ip_address {
    subnet_id = var.subnet_id_1
  }

  ip_address {
    subnet_id = var.subnet_id_2
  }

  tags = {
    Name = "OnPrem-DNS-Resolver"
  }
}

resource "aws_route53_resolver_rule" "onprem_dns_forwarding_rule" {
  domain_name          = var.on_prem_domain_name
  name                 = "onprem-dns-forwarding-rule"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.onprem_resolver_endpoint.id

  target_ip {
    ip = var.on_prem_dns_server_ip_1
  }

  target_ip {
    ip = var.on_prem_dns_server_ip_2
  }

  tags = {
    Name = "OnPrem-DNS-Forwarding-Rule"
  }
}

resource "aws_route53_resolver_rule_association" "dns_rule_association" {
  resolver_rule_id = aws_route53_resolver_rule.onprem_dns_forwarding_rule.id
  vpc_id           = var.vpc_id
}

# --- 4. Security Group for DNS Resolver ---
resource "aws_security_group" "dns_resolver_sg" {
  name        = "snowflake-dns-resolver-sg"
  description = "Allows DNS queries to on-premise DNS servers"
  vpc_id      = var.vpc_id

  egress {
    description = "DNS UDP to on-premise server 1"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["${var.on_prem_dns_server_ip_1}/32"]
  }

  egress {
    description = "DNS UDP to on-premise server 2"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["${var.on_prem_dns_server_ip_2}/32"]
  }

  egress {
    description = "DNS TCP to on-premise server 1"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["${var.on_prem_dns_server_ip_1}/32"]
  }

  egress {
    description = "DNS TCP to on-premise server 2"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["${var.on_prem_dns_server_ip_2}/32"]
  }

  tags = {
    Name = "Snowflake-DNS-Resolver-SG"
  }
}

# --- 5. Network Routing (Transit Gateway) ---
resource "aws_route" "tgw_route_1" {
  route_table_id         = var.route_table_id_1
  destination_cidr_block = var.on_prem_cidr
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "tgw_route_2" {
  route_table_id         = var.route_table_id_2
  destination_cidr_block = var.on_prem_cidr
  transit_gateway_id     = var.transit_gateway_id
}

# --- 6. Network Access Control Lists (NACLs) ---
resource "aws_network_acl" "nlb_nacl" {
  vpc_id     = var.vpc_id
  subnet_ids = [var.subnet_id_1, var.subnet_id_2]

  tags = {
    Name = "Snowflake-NLB-NACL"
  }
}

resource "aws_network_acl_rule" "inbound_from_snowflake" {
  network_acl_id = aws_network_acl.nlb_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.snowflake_vpc_cidr
  from_port      = var.database_port
  to_port        = var.database_port
}

resource "aws_network_acl_rule" "inbound_from_onprem" {
  network_acl_id = aws_network_acl.nlb_nacl.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.on_prem_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "outbound_to_onprem" {
  network_acl_id = aws_network_acl.nlb_nacl.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.on_prem_cidr
  from_port      = var.database_port
  to_port        = var.database_port
}

resource "aws_network_acl_rule" "outbound_to_snowflake" {
  network_acl_id = aws_network_acl.nlb_nacl.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.snowflake_vpc_cidr
  from_port      = 1024
  to_port        = 65535
}
