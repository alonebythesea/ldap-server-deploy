provider "aws" {
	region = "us-east-1"
}


data "aws_vpc" "default" {
	default = true
}

data "aws_subnet_ids" "all" {
	vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group" "allow_ssh" {
	name = "allow_ssh"
	vpc_id = data.aws_vpc.default.id
	
	ingress {
	  from_port   = 22
	  to_port     = 22
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

resource "aws_security_group" "allow_internal" {
	name = "allow_internal"
	vpc_id = data.aws_vpc.default.id
	
	ingress {
	  from_port   = 0
	  to_port     = 65535
          protocol    = "tcp"
	  cidr_blocks = [data.aws_vpc.default.cidr_block]
	}
}



resource "aws_security_group" "allow_http" {
	name = "allow_http"
	vpc_id = data.aws_vpc.default.id

	ingress {
	  from_port   = 80
	  to_port     = 80
	  protocol    = "tcp"
	  cidr_blocks = ["0.0.0.0/0"]
	}
}

resource "aws_instance" "ldap-server" {
	count 	      	       = 1
	ami           	       = "ami-0083662ba17882949"
	instance_type 	       = "t1.micro"
	availability_zone      = "us-east-1a" 
	key_name      	       = "my-key"
	vpc_security_group_ids = [aws_security_group.allow_internal.id, aws_security_group.allow_ssh.id, aws_security_group.allow_http.id]
	
	connection {
		type = "ssh"
		host = self.public_ip 
		user = "centos"
		private_key = file("~/.ssh/my-key.pem") 
	}
	
	provisioner "file" {

		source = "."
		destination = "/tmp"
	}

	provisioner "remote-exec" {
		inline = [
			"chmod +x /tmp/ldap-server-provision.sh",
			"cd /tmp",
			"sudo ./ldap-server-provision.sh",
		]
	}

}

resource "aws_instance" "ldap-client" {
	count 	      	       	= 1
	ami           	       	= "ami-0083662ba17882949"
	instance_type 	       	= "t1.micro"
	availability_zone      	= "us-east-1a" 
	key_name      	       	= "my-key"
	vpc_security_group_ids 	= [aws_security_group.allow_internal.id, aws_security_group.allow_ssh.id]

	connection {
		type = "ssh"
		host = self.public_ip 
		user = "centos"
		private_key = file("~/.ssh/my-key.pem") 
	}
	
	provisioner "file" {

		source = "."
		destination = "/tmp"
	}

	provisioner "remote-exec" {
		inline = [
			"sudo yum -y install openldap-clients nss-pam-ldapd",
      			"sudo authconfig --enableldap --enableldapauth --ldapserver=${aws_instance.ldap-server[0].private_ip} --ldapbasedn='dc=devopslab,dc=com' --enablemkhomedir --updateall",
			"chmod +x /tmp/ldap-client-provision.sh",
			"sudo /tmp/ldap-client-provision.sh",
		]
	}
} 
