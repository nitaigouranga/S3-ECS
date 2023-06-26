resource "aws_ecs_cluster" "demo-ecs-cluster" {
  name = "ecs-cluster-Anitha"
}

resource "aws_ecs_service" "demo-ecs-service-two" {
  name            = "demo-app"
  cluster         = aws_ecs_cluster.demo-ecs-cluster.id
  task_definition = aws_ecs_task_definition.demo-ecs-task-definition.arn
  launch_type     = "FARGATE"
  platform_version = "LATEST"
  network_configuration {
    
 subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}"]
    assign_public_ip = true     # Provide the containers with public IPs
  }
  desired_count = 1
}

resource "aws_ecs_task_definition" "demo-ecs-task-definition" {
  family                   = "ecs-task-definition-demo"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = "1024"
  cpu                      = "512"
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
  container_definitions    = <<EOF
[
  {
    "name": "demo-container",
    "image": "182663769864.dkr.ecr.us-west-2.amazonaws.com/app-repo",
    "memory": 1024,
    "cpu": 512,
    "essential": true,
   
    "portMappings": [
      {
        "containerPort": 80,
          "hostPort": 80
          
      }
    ]
  }
]

  EOF
}
resource "aws_iam_role" "ecsTaskExecutionRole" {
 name               = "ecs34TaskExecutionRole"
 assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

# generates an iam policy document in json format for the ecs task execution role
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
# attach ecs task execution policy to the iam role
resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
 
 policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

