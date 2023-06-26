resource "aws_s3_bucket" "uploads" {
  bucket = "myproject-uploads2019"


}
resource "aws_s3_bucket_notification" "name" {
  bucket = aws_s3_bucket.uploads.id
  eventbridge = true
}