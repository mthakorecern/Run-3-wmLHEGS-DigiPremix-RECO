#!/bin/bash

set -euo pipefail

JOBID="${1:?CRAB job ID is required}"

shift

DATASET_NAME=""
FRAGMENT_MODULE=""

for ARG in "$@"; do
    case "${ARG}" in
        datasetName=*)
            DATASET_NAME="${ARG#datasetName=}"
            ;;
        fragmentModule=*)
            FRAGMENT_MODULE="${ARG#fragmentModule=}"
            ;;
        *)
            echo "ERROR: unknown script argument: ${ARG}"
            exit 1
            ;;
    esac
done

if [ -z "${DATASET_NAME}" ]; then
    echo "ERROR: datasetName was not supplied"
    exit 1
fi


if [ -z "${FRAGMENT_MODULE}" ]; then
    echo "ERROR: fragmentModule was not supplied"
    exit 1
fi


if ! [[ "${JOBID}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: invalid CRAB job ID: ${JOBID}"
    exit 1
fi


PILEUP_DATASET= "/Neutrino_E-10_gun/RunIIISummer24PrePremix-Premixlib2024_140X_mcRun3_2024_realistic_v26-v1/PREMIX"

# CRAB numbering starts from 1. Original production convention: JOBINDEX = JOBID - 1
# RSEED = JOBINDEX * MAX_NTHREADS * 4 + 1001

NTHREADS=8
SEED_STRIDE_THREADS=8

JOBINDEX=$((JOBID - 1))
RSEED=$((JOBINDEX * SEED_STRIDE_THREADS * 4 + 1001))

# Obtain CRAB's event count for this job.
NEVENTS=$(python3 - <<'PY'
from PSet import process
print(process.maxEvents.input.value())
PY
)

if ! [[ "${NEVENTS}" =~ ^[0-9]+$ ]] || [ "${NEVENTS}" -le 0 ]; then
    echo "ERROR: invalid CRAB event count: ${NEVENTS}"
    exit 1
fi

echo "CRAB Job ID   : ${JOBID}"
echo "Job index     : ${JOBINDEX}"
echo "Random seed   : ${RSEED}"
echo "Events/job    : ${NEVENTS}"
echo "Threads       : ${NTHREADS}"
echo "Dataset       : ${DATASET_NAME}"
echo "Fragment      : ${FRAGMENT_MODULE}"
echo "Premix        : ${PILEUP_DATASET}"
echo "CMSSW         : ${CMSSW_VERSION:-unset}"
echo "SCRAM_ARCH    : ${SCRAM_ARCH:-unset}"
echo "Host          : $(hostname)"
echo "PWD           : $(pwd)"

if [ "${CMSSW_VERSION:-}" != "CMSSW_14_0_18" ]; then
    echo "ERROR: expected CMSSW_14_0_18"
    exit 1
fi

echo " STEP 1/3 : wmLHEGS"

# in the event content and datatier, we remove LHE so that output is one file and not multiple files
cmsDriver.py \
    "Configuration/GenProduction/python/${FRAGMENT_MODULE}.py" \
    --python_filename wmLHEGS_cfg.py \
    --eventcontent RAWSIM \
    --datatier GEN-SIM \
    --fileout file:wmLHEGS.root \
    --conditions 140X_mcRun3_2024_realistic_v26 \
    --beamspot DBrealistic \
    --step LHE,GEN,SIM \
    --geometry DB:Extended \
    --era Run3_2024 \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --mc \
    --nThreads "${NTHREADS}" \
    --no_exec \
    -n "${NEVENTS}"

cat > wmLHEGS_runtime.py <<EOF
import FWCore.ParameterSet.Config as cms

from wmLHEGS_cfg import process
from PSet import process as crab_process

process.maxEvents = (
    crab_process.maxEvents
)

for name in (
    "firstRun",
    "firstLuminosityBlock",
    "firstEvent",
    "numberEventsInLuminosityBlock",
    "numberEventsInRun",
):

    if hasattr(
        crab_process.source,
        name,
    ):

        setattr(
            process.source,
            name,
            getattr(
                crab_process.source,
                name,
            ),
        )

process.RandomNumberGeneratorService.externalLHEProducer.initialSeed = (
    cms.untracked.uint32(
        ${RSEED}
    )
)
EOF

echo
echo "+ cmsRun wmLHEGS_runtime.py"
echo

cmsRun \
    -j wmLHEGS_FrameworkJobReport.xml \
    wmLHEGS_runtime.py

if [ ! -s wmLHEGS.root ]; then
    echo "ERROR: wmLHEGS.root was not produced"
    exit 1
fi

echo
echo "wmLHEGS complete:"
ls -lh wmLHEGS.root
echo

echo " STEP 2/3 : DIGIPremix"

cmsDriver.py \
    --python_filename DIGIPremix_cfg.py \
    --eventcontent PREMIXRAW \
    --datatier GEN-SIM-RAW \
    --filein file:wmLHEGS.root \
    --fileout file:DIGIPremix.root \
    --conditions 140X_mcRun3_2024_realistic_v26 \
    --step DIGI,DATAMIX,L1,DIGI2RAW,HLT:2024v14 \
    --pileup_input "dbs:${PILEUP_DATASET}" \
    --geometry DB:Extended \
    --era Run3_2024 \
    --datamix PreMix \
    --procModifiers premix_stage2 \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --mc \
    --nThreads "${NTHREADS}" \
    --no_exec \
    -n -1


echo
echo "+ cmsRun DIGIPremix_cfg.py"
echo


cmsRun \
    -j DIGIPremix_FrameworkJobReport.xml \
    DIGIPremix_cfg.py


if [ ! -s DIGIPremix.root ]; then
    echo "ERROR: DIGIPremix.root was not produced"
    exit 1
fi


echo
echo "DIGIPremix complete:"
ls -lh DIGIPremix.root
echo

rm -f wmLHEGS.root


echo " STEP 3/3 : RECO"

cmsDriver.py \
    --python_filename RECO_cfg.py \
    --eventcontent AODSIM \
    --datatier AODSIM \
    --filein file:DIGIPremix.root \
    --fileout file:RECO.root \
    --conditions 140X_mcRun3_2024_realistic_v26 \
    --step RAW2DIGI,L1Reco,RECO,RECOSIM \
    --geometry DB:Extended \
    --era Run3_2024 \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --mc \
    --nThreads "${NTHREADS}" \
    --no_exec \
    -n -1

echo
echo "+ cmsRun RECO_cfg.py"
echo


# IMPORTANT:
# This is the FINAL processing step.# CRAB needs the final FrameworkJobReport.xml for:
#   RECO.root

cmsRun \
    -j FrameworkJobReport.xml \
    RECO_cfg.py


if [ ! -s RECO.root ]; then
    echo "ERROR: RECO.root was not produced"
    exit 1

fi

echo
echo "RECO complete:"
ls -lh RECO.root
echo
rm -f DIGIPremix.root
echo " FullRECO SUCCESS"

echo "Final output:"
ls -lh RECO.root

