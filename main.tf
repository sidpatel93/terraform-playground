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
    values = [ data.aws_vpc.default ]
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
  security_groups = [ aws_security_group.instance-security-group ]
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

# load balance to distribute traffic to the EC2 instances in the auto scaling group
resource "aws_lb" "my-sample-lb" {
  name               = "my-sample-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_listener" "my-sample-listener" {
  load_balancer_arn = aws_lb.my-sample-lb.arn
  port              = var.server_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my-sample-tg.arn
  }
}

resource "aws_lb_target_group" "my-sample-tg" {
  name     = "my-sample-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
}



# output "instance_public_ip" {
#   description = "output details of the sample ec2 instance"
#   value = aws_instance.my-sample-instance.public_ip
# }