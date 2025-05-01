#!/bin/sh

/bin/terraform init
/bin/terraform apply -auto-approve
sleep 1200
/bin/terraform destroy -auto-approve