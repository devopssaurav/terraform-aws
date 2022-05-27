terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
  backend "s3" {
    bucket = "terraform-aws-backend"
    key    = "./terraform/terraform.tfstate"
    region = "us-east-2"
  }
}

provider "aws" {

  shared_credentials_file = "~/.aws/credentials"
  profile                 = "default"
  region                  = "us-east-2"
}

# 1. Create a vpc

resource "aws_vpc" "terraform-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "terraform-vpc"
  }
}

# 2. Create IG

resource "aws_internet_gateway" "terraform-gw" {
  vpc_id = aws_vpc.terraform-vpc.id

  tags = {
    Name = "terraform-ig"
  }
}

# 3. Create Custom route table

resource "aws_route_table" "terraform-route-table" {
  vpc_id = aws_vpc.terraform-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terraform-gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.terraform-gw.id
  }

  tags = {
    Name = "terraform-route-table"
  }
}

# 4. Create a subnet

resource "aws_subnet" "terraform-subnet" {
  vpc_id            = aws_vpc.terraform-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "terraform-subnet"
  }
}

# 5. Associate subnet with route table

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.terraform-subnet.id
  route_table_id = aws_route_table.terraform-route-table.id
}

# 6. Create Security Group to allow ports 22, 80, 443

resource "aws_security_group" "web" {
  name        = "allow_web"
  description = "Allow WEB inbound traffic"
  vpc_id      = aws_vpc.terraform-vpc.id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}



# 7. Create a Network Interface with an ip in the subnet that was created in step 4

resource "aws_network_interface" "terraform-network-interface" {
  subnet_id       = aws_subnet.terraform-subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.web.id]


}

# 8. Assign elastic IP to the network interface created in step 7

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.terraform-network-interface.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [
    aws_internet_gateway.terraform-gw,
    aws_instance.web
  ]
}

# 9. Create ubuntu server and install/enable NGINX 

resource "aws_instance" "web" {
  ami               = "ami-0aeb7c931a5a61206"
  instance_type     = "t3.micro"
  availability_zone = "us-east-2a"
  key_name          = "terraform"
  network_interface {

    network_interface_id = aws_network_interface.terraform-network-interface.id
    device_index         = 0
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install nginx -y
                sudo systemctl start nginx
                sudo systemctl enable nginx
                sudo bash -c 'echo Hello World! > /var/www/html/index.html'
                EOF
  tags = {
    Name = "HelloWorld"
  }

}




