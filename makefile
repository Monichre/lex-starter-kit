build:
	cd functions/oscarbot && yarn install && zip -r ../../oscarbot.zip .

upload:
	aws s3 cp oscarbot.zip s3://`terraform output bucket`/functions/oscarbot.zip

create:
	aws lambda create-function \
		--region us-east-1 \
		--function-name intentGetStars \
		--runtime nodejs6.10 \
		--handler intentGetStars.handler \
		--role `terraform output role`\
		--code S3Bucket=`terraform output bucket`,S3Key=functions/oscarbot.zip

update:
	aws lambda update-function-code \
    --region us-east-1 \
    --function-name intentGetStars \
    --s3-bucket `terraform output bucket` \
    --s3-key functions/oscarbot.zip

release: deploy
	VERSION=$$(aws lambda publish-version --region us-east-1 --function-name intentGetStars | jq -r .Version); \
	aws lambda update-alias --function-name intentGetStars --region us-east-1 --function-version $$VERSION --name PROD

deploy: build upload update

setup: build upload create

# Creates the infrastructure required.
infra-up:
	terraform apply

# Destoys the infrastructure.
infra-down:
	terraform destroy
