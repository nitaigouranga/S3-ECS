# Trigger an ECS job when an S3 upload completes

![s3-eb-ecs](https://github.com/nitaigouranga/S3-ECS/assets/134625966/00a11455-9270-456d-bda8-91d4acf33550)

### The first step is to get CloudWatch to provide events for uploads in the S3 bucket. This isn’t enabled by default and requires some Cloudtrail magic.
##### s3bucket.tf
```
# S3 bucket to receive the file uploads.
resource "aws_s3_bucket" "uploads" {
  bucket = "myproject-uploads2019"


}
resource "aws_s3_bucket_notification" "name" {
  bucket = aws_s3_bucket.uploads.id
  eventbridge = true
}
```
##### cloudtrail.tf
```
#S3 bucket for the cloudtrail data. The policy essentially allows Cloudtrail to write to this bucket.
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "myproject-cloudtrail2019"
  force_destroy = true
 policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::myproject-cloudtrail2019"
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::myproject-cloudtrail2019/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    }
  ]
}
POLICY
}
# This creates a new Cloudtrail and instructs it to report what's  going on with objects in the uploads bucket
resource "aws_cloudtrail" "uploads" {
  name           = "myproject-cloudtrail-uploads"
  s3_bucket_name = "${aws_s3_bucket.cloudtrail.id}"
  s3_key_prefix  = "uploads"
  event_selector {
    read_write_type           = "All"
    include_management_events = false
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.uploads.arn}/"]
    }
  }
}
```
### With that, any object activity in the uploads will be available as a Cloudwatch event. The next step is to setup a ECS cluster and then set up a rule that listens for these events and triggers the ECS job.
##### ECScluster.tf
```
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
```
##### AZ.tf
```
resource "aws_default_vpc" "default_vpc" {
}
# Provide references to your default subnets
resource "aws_default_subnet" "default_subnet_a" {
  # Use your own region here but reference to subnet 1a
  availability_zone = "us-west-2a"
}
resource "aws_default_subnet" "default_subnet_b" {
  # Use your own region here but reference to subnet 1b
  availability_zone = "us-west-2b"
}
```
##### eventbridge.tf
```
resource "aws_cloudwatch_event_rule" "uploads" {
  name        = "myproject-capture-uploads"
  description = "Capture S3 events on uploads bucket"
  event_pattern = <<PATTERN
{
   "source": [
    "aws.s3"
  ],
  "detail-type": [
    "AWS API Call via CloudTrail"
  ],
  "detail": {
    "eventSource": [
      "s3.amazonaws.com"
    ],
    "eventName": [
      "PutObject","CompleteMultipartUpload"
    ],
     "requestParameters": {
      "bucketName": ["${aws_s3_bucket.uploads.id}"]
     }
  }
}
PATTERN
}
# The target is the glue between the event rule and the ECS task definition. This instructs Cloudwatch to run the ECS job when the rule matches an event.
resource "aws_cloudwatch_event_target" "uploads" {
  target_id = "myproject-process-uploads"
  arn       = "${aws_ecs_cluster.demo-ecs-cluster.arn}"
  rule      = "${aws_cloudwatch_event_rule.uploads.name}"
  role_arn  = "${aws_iam_role.uploads_events.arn}"
  ecs_target {
    launch_type = "FARGATE"
    platform_version = "LATEST"
    task_count          = 1 # Launch one container / event
    task_definition_arn = "${aws_ecs_task_definition.demo-ecs-task-definition.arn}"
     network_configuration  {
      subnets         = var.vpc_subnet_ids
      assign_public_ip= true
       }
  }
}
# This is the standard role to allow Cloudwatch to act on your behalf
resource "aws_iam_role" "uploads_events" {
  name = "myproject-uploads-events"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}
# This authorizes cloudwatch to run an ECS task with any given role. The task needs the role to access the S3 bucket.
resource "aws_iam_role_policy" "ecs_events_run_task_with_new_role" {
  name = "myproject-uploads-run-task-with-new-role"
  role = "${aws_iam_role.uploads_events.id}"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ecs:RunTask",
       
    "Resource": "${replace(aws_ecs_task_definition.demo-ecs-task-definition.arn, "/:\\d+$/", ":*")}"
    }
  ]
}
POLICY
}
```
##### variable.tf
```
variable "vpc_subnet_ids" {
  type = list
  default = ["subnet-042b6af4c16df551d", "subnet-081a1ef0b329162c2", "subnet-04361dd9f04c87f90","subnet-0b548d8dfb490b947"]
}
```
#### At this point, if you upload a file into the S3 bucket, you should see a FARGATE container get launched on ECS. There’s one problem the container has no idea which object in the bucket triggered the job.
###### eventbridgeinputtransformer.tf( Adding input transformer to evenbridge.tf)
```
resource "aws_cloudwatch_event_rule" "uploads" {
  name        = "myproject-capture-uploads"
  description = "Capture S3 events on uploads bucket"
  event_pattern = <<PATTERN
{
    "source": [
    "aws.s3"
  ],
  "detail-type": [
    "AWS API Call via CloudTrail"
  ],
  "detail": {
    "eventSource": [
      "s3.amazonaws.com"
    ],
    "eventName": [
      "PutObject","CompleteMultipartUpload"
    ],
     "requestParameters": {
      "bucketName": ["${aws_s3_bucket.uploads.id}"]
     }
  }
}
PATTERN
}
resource "aws_cloudwatch_event_target" "uploads" {
  target_id = "myproject-process-uploads"
  arn       = "${aws_ecs_cluster.demo-ecs-cluster.arn}"
  rule      = "${aws_cloudwatch_event_rule.uploads.name}"
  role_arn  = "${aws_iam_role.uploads_events.arn}"
  ecs_target {
    launch_type = "FARGATE"
    platform_version = "LATEST"
    task_count          = 1 # Launch one container / event
    task_definition_arn = "${aws_ecs_task_definition.demo-ecs-task-definition.arn}"
      network_configuration  {
     subnets         = var.vpc_subnet_ids
      assign_public_ip= true
        }
   }
 input_transformer  {
    # This section plucks the values we need from the event
   input_paths = {
     s3_bucket = "$.detail.requestParameters.bucketName"
     s3_key    = "$.detail.requestParameters.key"
   }
    #This is the input template for the ECS task. The variables
    # defined in input_path above are available. This passes the 
    # bucket name and object key as environment variables to the
    # task
    input_template = <<TEMPLATE
{
  "containerOverrides": [
   {
     "name": "demo-container",
      "environment": [
       { "name": "S3_BUCKET", "value": <s3_bucket> },
       { "name": "S3_KEY", "value": <s3_key> }
      ]
    }
  ]
}
TEMPLATE
  }
}
resource "aws_iam_role" "uploads_events" {
  name = "myproject-uploads-events"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}
resource "aws_iam_role_policy" "ecs_events_run_task_with_new_role" {
  name = "myproject-uploads-run-task-with-new-role"
  role = "${aws_iam_role.uploads_events.id}"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ecs:RunTask",
        "Resource": "${replace(aws_ecs_task_definition.demo-ecs-task-definition.arn, "/:\\d+$/", ":*")}"
    }
  ]
}
POLICY
}
```
### The container now knows which object to go fetch for processing.



