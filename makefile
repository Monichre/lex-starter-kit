REGION := us-east-1
FUNCTION := serverless-summit

# Helper variables we use to check if things exist.
# Consider moving into a script of its own, and checking we are logged in.
JQ_EXISTS := $(shell command -v jq 2> /dev/null)
AWS_CLI_EXISTS := $(shell command -v aws 2> /dev/null)

# Lints the lambda function.
lint:
	cd lambda && npm install && npm run lint

# Tests the lambda function.
test:
	cd lambda && npm install && npm test

# Builds the lambda function. Copies it to a clean location first so that we
# can eliminate any non-production node modules.
build:
	rm -rf ./artifacts/lambda
	cp -R ./lambda ./artifacts/lambda
	rm -rf ./artifacts/lambda/node_modules
	cd ./artifacts/lambda && npm install --production && zip -r ../$(FUNCTION).zip .

# Creates a coverage report.
coverage:
	cd lambda && npm install && npm run coverage

# Sets up the core AWS resources.
setup: check-dependencies build
	# Create the bucket. If it fails, it's probably because the name is in use.
	aws s3 mb s3://$(BUCKET) --region $(REGION)
	aws s3 cp ./artifacts/$(FUNCTION).zip s3://$(BUCKET)/$(FUNCTION).zip
	
	# Create the role and set the policy.
	aws iam create-role --role-name "$(FUNCTION)-role" --assume-role-policy-document file://aws/lambda-policy-doc.json
	aws iam put-role-policy --role-name "$(FUNCTION)-role" --policy-name "$(FUNCTION)-policy" --policy-document file://aws/policy.json
	sleep 10 # roles take a while to setup
	
	# Create the bucket and lambda function.
	ACCOUNT_ID=`aws sts get-caller-identity --output text --query 'Account'`; \
	aws lambda create-function \
		--region $(REGION) \
		--function-name $(FUNCTION) \
		--runtime nodejs6.10 \
		--handler index.handler \
		--environment="Variables={OSCAR_GITHUB_USERNAME=\"$(OSCAR_GITHUB_USERNAME)\",OSCAR_GITHUB_PASSWORD=\"$(OSCAR_GITHUB_PASSWORD)\",DEBUG=oscar}" \
		--role "arn:aws:iam::$$ACCOUNT_ID:role/$(FUNCTION)-role" \
		--code S3Bucket=$(BUCKET),S3Key=$(FUNCTION).zip

# Deploys updates.
deploy: build
	aws s3 cp ./artifacts/$(FUNCTION).zip s3://$(BUCKET)/$(FUNCTION).zip
	aws lambda update-function-code \
		--region $(REGION) \
		--function-name $(FUNCTION) \
		--s3-bucket $(BUCKET) \
		--s3-key $(FUNCTION).zip
	
	# Update the slots.
	./scripts/deploy-slots.sh deploy-slots $(REGION) "lex/slots/*.json"
	
	# Update the intents.
	ACCOUNT_ID=`aws sts get-caller-identity --output text --query 'Account'`; \
	./scripts/deploy-intents.sh deploy-intents "$(REGION)" "$(FUNCTION)" $$ACCOUNT_ID `find ./lex/intents -name '*.json'`
	
	# Update the bot.
	./scripts/deploy-bot.sh deploy-bot "$(REGION)" "lex/bot/OscarBot.json"

# Destroys some resources. Still work in progress for others.
destroy:
	aws lambda delete-function --function-name $(FUNCTION) || true
	aws iam delete-role-policy --role-name "$(FUNCTION)-role" --policy-name "$(FUNCTION)-policy" || true
	aws iam delete-role --role-name "$(FUNCTION)-role" || true
	aws s3 rb s3://$(BUCKET) --force || true

cli:
	cd oscar-cli; npm build; npm link;

# Utility to show all utterances.
utterances:
	for file in "./lex/intents/*.json"; do cat $$file | jq .sampleUtterances[0]; done

check-dependencies:
ifndef BUCKET
	$(error "Environment variable $$BUCKET must be set.")
endif
ifndef OSCAR_GITHUB_USERNAME
	$(error "Environment variable $$OSCAR_GITHUB_USERNAME must be set.")
endif
ifndef OSCAR_GITHUB_PASSWORD
	$(error "Environment variable $$OSCAR_GITHUB_PASSWORD must be set.")
endif
ifndef JQ_EXISTS
	$(error "Error: jq must be installed.")
endif
ifndef AWS_CLI_EXISTS
	$(error "Error: aws-cli must be installed.")
endif
