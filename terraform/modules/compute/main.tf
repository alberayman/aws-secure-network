data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------- Web server in a PRIVATE subnet, managed only through SSM ----------
resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_tokens = "required" # IMDSv2 only, blocks SSRF credential theft
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nginx
    echo "<h1>secnet web server</h1><p>$(hostname)</p>" > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOT

  tags = { Name = "${var.name}-web" }
}

# ---------- Internet-facing Application Load Balancer ----------
resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "web" {
  name        = "${var.name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
  }
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ---------- RDS MySQL, private, encrypted, password in Secrets Manager ----------
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "this" {
  identifier                  = "${var.name}-db"
  engine                      = "mysql"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  db_name                     = "appdb"
  username                    = "admin"
  manage_master_user_password = true # AWS generates and stores it; never in code
  db_subnet_group_name        = aws_db_subnet_group.this.name
  vpc_security_group_ids      = [aws_security_group.rds.id]
  publicly_accessible         = false
  storage_encrypted           = true
  multi_az                    = false # lab cost saving; production = true
  backup_retention_period     = 1
  deletion_protection         = false # lab only
  skip_final_snapshot         = true  # lab only
}
