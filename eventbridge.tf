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
    //subnets = ["${aws_default_subnet.default_subnet_a}","${aws_default_subnet.default_subnet_b}"]
     // = [subnet-042b6af4c16dfsubnets551d, subnet-081a1ef0b329162c2, subnet-04361dd9f04c87f90, subnet-0b548d8dfb490b947]
      subnets         = var.vpc_subnet_ids
      assign_public_ip= true
      
      }
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