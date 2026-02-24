provider "aws" {
  region = "us-east-1"
}

# Default vpc data source
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [ data.aws_vpc.default.id ]
  }
}

variable "server_port" {
  description = "port used for the server instance"
  type = number
  default = 8080
}

# launch configuration for the EC2 instance
resource "aws_launch_configuration" "my-sample-instance" {
  image_id = "ami-0b6c6ebed2801a5cb"
  instance_type = "t2.micro"
  security_groups = [ aws_security_group.instance-security-group.id ]
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World!" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
}

# auto scaling group to manage the EC2 instance
resource "aws_autoscaling_group" "my-sample-instance-asg" {
  name = "my-sample-instance-asg"
  launch_configuration = aws_launch_configuration.my-sample-instance.id
  vpc_zone_identifier = data.aws_subnets.default.ids
  min_size = 2
  max_size = 3
  target_group_arns = [aws_lb_target_group.asg-target-group.arn]
  health_check_type = "ELB"
  tag {
    key = "Name"
    value = "terraform-test"
    propagate_at_launch = true
  }
  # ensure that new launch configuration is created before destroying the old one
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "instance-security-group" {
  name        = "instance-security-group"
  description = "Allow HTTP traffic on port ${var.server_port}"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Load balancer security group to allow incoming traffic on port 80 and allow outgoing traffic to the EC2 instances in the auto scaling group
resource "aws_security_group" "alb-security-group" {
  name = "terraform-alb-security-group"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] 
  }
}

# load balance to distribute traffic to the EC2 instances in the auto scaling group
resource "aws_lb" "my-sample-lb" {
  name               = "my-sample-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [ aws_security_group.alb-security-group.id ]
}

resource "aws_lb_listener" "my-sample-listener" {
  load_balancer_arn = aws_lb.my-sample-lb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code = 404
      message_body = "404: Page Not Found"
    }
  }
}

resource "aws_lb_target_group" "asg-target-group" {
  name     = "my-sample-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "my-sample-listener-rule" {
  listener_arn = aws_lb_listener.my-sample-listener.arn
  priority     = 100
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg-target-group.arn
  }
  condition {
    path_pattern {
      values = ["*"]
    }
  }
  
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value = aws_lb.my-sample-lb.dns_name
}