# Copyright Contributors to the Open Cluster Management project

#!/bin/bash
set -e
# set -x
while getopts o:i:dh flag
do
  case "${flag}" in
    o) OUT="-o ${OPTARG}";;
    i) IN="--values ${OPTARG}";;
    d) DEL="--delete";;
    h) HELP="help"
  esac
done
if [ -n "$HELP" ]
then
  echo "deploy.sh [-i values.yaml] [-o output-file] [-d] [-h]"
  echo "-i: the path to the values.yaml, default values.yaml"
  echo "-o: output-file: generate an output-file instead of applying"
  echo "-d: When set the cluster will be destroyed"
  echo "-h: this help"
  exit 0
fi
INSTALL_DIR=$(dirname $0)
if [ -z ${IN+x} ]
then
  IN="-values values.yaml"
fi
PARAMS="$(applier -d $INSTALL_DIR/params.yaml $IN -o /dev/stdout --silent)"
CLOUD=$(echo "$PARAMS" | grep "cloud:" | cut -d ":" -f2 | sed 's/^ //')
if [ $CLOUD != "aws" ] && [ $CLOUD != "azure" ] && [ $CLOUD != "gcp" ]  && [ $CLOUD != "vsphere" ]
then
   echo -e $CLOUD" not supported\nOnly aws, azure, gcp and vsphere are supported"
   exit 1
fi
NAME=$(echo "$PARAMS" | grep "name:" | cut -d ":" -f2 | sed 's/^ //')
if [ -z "CLOUD" ]
then
  echo "Missing cloud type in value.yaml"
  exit 1
fi
if [ -z "$NAME" ]
then
  echo "Missing cluster name in value.yaml"
  exit 1
fi

# Before deploy, make sure namespace does not exist already
if [ -z ${DEL+x} ]
then
  set +e
  oc get ns $NAME > /dev/null 2>&1
  if [ $? == 0 ]
  then
    echo $NAME" already exits"
    exit 1
  fi
  set -e
fi

EXT_VALUES=$(cat > /dev/stdout << EOF
pullSecret:
$(oc get secret pull-secret -n openshift-config -oyaml | sed 's/^/  /')
installConfig:
$(applier -d $INSTALL_DIR/hub/$CLOUD/install_config.yaml $IN -o /dev/stdout --silent | sed 's/^/  /')
EOF)

# Create the managed cluster
if [ -z ${DEL+x} ]
then
  echo "$EXT_VALUES" | applier -d $INSTALL_DIR/hub/common $IN $OUT --silent $VERBOSE
# Delete the managed cluster
else
  echo "$EXT_VALUES" | applier -d $INSTALL_DIR/hub/common/managed_cluster_cr.yaml $IN $DEL $OUT $VERBOSE
  echo "$EXT_VALUES" | applier -d $INSTALL_DIR/hub/common/cluster_deployment_cr.yaml -$IN $DEL $OUT $VERBOSE
fi
