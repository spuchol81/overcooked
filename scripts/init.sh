#!/bin/bash 
set -euxo pipefail

######### ENV ##########

ENV_FILE_PARENT_DIR=/home/kubernetes-vm
ENV_FILE=$ENV_FILE_PARENT_DIR/env
export $(cat $ENV_FILE | xargs)

########## Solution view ##########

/opt/workshops/elastic-view.sh -v oblt


########### AI SETUP ###########
/opt/workshops/elastic-llm.sh -k true