# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"  # Replace with your desired region
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create Public and Private Subnets
resource "aws_subnet" "public" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = element(aws_vpc.main.cidr_blocks, count.index)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)

  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count = 2
  vpc_id = aws_vpc.main.id
  cidr_block = element(aws_vpc.main.cidr_blocks, count.index + 2)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)

  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Create a NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id     = aws_subnet.public[0].id
}

# Create an EIP for the NAT Gateway
resource "aws_eip" "nat_gateway" {
}

# Create a Route Table for Public Subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

# Create a Route Table for Private Subnets
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

# Associate Route Tables with Subnets
resource "aws_route_table_association" "public_route_table_assoc" {
  count           = length(aws_subnet.public)
  subnet_id       = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_assoc" {
  count           = length(aws_subnet.private)
  subnet_id       = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.private_route_table.id
}

# Create a Security Group for the EC2 Instance
resource "aws_security_group" "ec2_security_group" {
  name        = "ec2-security-group"
  vpc_id      = aws_vpc.main.id
  description = "Allow SSH and HTTP traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

# Create an EC2 Instance in a Private Subnet
resource "aws_instance" "ec2_instance" {
  ami           = "ami-0c55b159cbfafe1f0"  # Replace with a suitable AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private[0].id
  security_groups = [aws_security_group.ec2_security_group.id]

  tags = {
    Name = "My React App Instance"
  }
}



###################If it is for ECS Fargate Task##########################
# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "react-app-cluster"
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach Policies for Task Execution Role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "react_app_task" {
  family                   = "react-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"                # 0.25 vCPU
  memory                   = "512"                # 512 MB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name        = "react-app"
      image       = "your-ecr-repo-url/react-app:latest"  # Update with your Docker image URI
      cpu         = 256
      memory      = 512
      essential   = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "react_app_service" {
  name            = "react-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.react_app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public.*.id
    security_groups = [aws_security_group.ec2_security_group.id]
    assign_public_ip = true
  }
}

# Create an Application Load Balancer for the ECS Service
resource "aws_lb" "ecs_alb" {
  name               = "ecs-react-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2_security_group.id]
  subnets            = aws_subnet.public.*.id
}

# Target Group for ECS Service
resource "aws_lb_target_group" "ecs_target_group" {
  name     = "ecs-react-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"
}

# Listener for Application Load Balancer
resource "aws_lb_listener" "ecs_listener" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
  }
}

# ECS Service Attachment to Target Group
resource "aws_lb_target_group_attachment" "ecs_service_attachment" {
  target_group_arn = aws_lb_target_group.ecs_target_group.arn
  target_id        = aws_ecs_service.react_app_service.id
  port             = 80
}
