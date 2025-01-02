provider "aws" {
  region = "us-east-1"  
}
       
resource "aws_s3_bucket" "original_images" {
  bucket = "pratty-source-bucket"
}

resource "aws_s3_bucket" "resized_images" {
  bucket = "pratty-destination-bucket"
}

resource "aws_sns_topic" "image_resized" {
  name = "image-resized-topic"
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Effect = "Allow"
      Sid    = ""
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy"
  role = aws_iam_role.lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.original_images.arn}/*",
          "${aws_s3_bucket.resized_images.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.image_resized.arn
      }
    ]
  })
}

resource "aws_lambda_function" "image_resizer" {
  function_name    = "image-resizer"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "CreateThumbnail.handler"
  runtime          = "python3.9"
  filename         = "${path.module}/CreateThumbnail.zip"
  source_code_hash = filebase64sha256("${path.module}/CreateThumbnail.zip")
  timeout          = 60
  layers = [
    "arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p39-pillow:1"
  ]
  environment {
    variables = {
      S3_Bucket = aws_s3_bucket.resized_images.bucket
      Topic_Arn = aws_sns_topic.image_resized.arn
    }
  }
}

resource "aws_lambda_permission" "allow_s3_to_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.original_images.arn
  function_name = aws_lambda_function.image_resizer.function_name
}

resource "aws_s3_bucket_notification" "image_uploaded" {
  bucket = aws_s3_bucket.original_images.bucket

  lambda_function {
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpeg"
    lambda_function_arn = aws_lambda_function.image_resizer.arn
  }

  depends_on = [aws_lambda_permission.allow_s3_to_invoke]
}

resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.image_resized.arn
  protocol  = "email"
  endpoint  = "spratyaksh85@gmail.com"
}
