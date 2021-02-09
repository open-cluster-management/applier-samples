#!/bin/bash
set -e
#set -x
while getopts o:i:dv:h flag
do 
  case "${flag}" in
    o) OUT="-o ${OPTARG}";;
    i) IN="-values ${OPTARG}";;
    d) DEL="-delete";;
    v) VERBOSE="-v ${OPTARG}";;
    h) HELP="help"
  esac
done
if [ -n "$HELP" ]
then
  echo "deploy.sh [-i values.yaml] [-o output-file] [-d] [-v [0-99]] [-h]"
  echo "-i: the path to the values.yaml, default values.yaml"
  echo "-o: output-file: generate an output-file instead of applying"
  echo "-d: When set the cluster will be destroyed"
  echo "-v: verbose level"
  echo "-h: this help"
  exit 0
fi
if [ -z ${INPUT+x} ]
then
  INPUT="-values values.yaml"
fi
PARAMS="$(applier -d params.yaml $IN -o /dev/stdout -s)"
CLOUD=$(echo "$PARAMS" | grep "cloud:" | cut -d ":" -f2 | sed 's/^ //')
if [ $CLOUD != "aws" ] && [ $CLOUD != "azure" ] && [ $CLOUD != "gcp" ]
then 
   echo -e $CLOUD" not supported\nOnly aws, azure and gcp are supported"
   exit 1
fi
NAME=$(echo "$PARAMS" | grep "name:" | cut -d ":" -f2 | sed 's/^ //')
if [ -z ${CLOUD+x} ] 
then
  echo "Missing cloud type in value.yaml"
  exit 1
fi
if [ -z ${NAME+x} ] 
then
  echo "Missing cluster name in value.yaml"
  exit 1
fi

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
$(applier -d hub/$CLOUD/install_config.yaml $IN -o /dev/stdout -s | sed 's/^/  /')
EOF)

if [ -z ${DEL+x} ]
then
    echo "$EXT_VALUES" | applier -d hub/common $IN $OUT -s $VERBOSE
else
    echo "$EXT_VALUES" | applier -d hub/common/managed_cluster_cr.yaml $IN $DEL $OUT $VERBOSE
    echo "$EXT_VALUES" | applier -d hub/common/cluster_deployment_cr.yaml -$IN $DEL $OUT $VERBOSE
fi 