import FWCore.ParameterSet.Config as cms

process = cms.Process("BOOKKEEPING")
process.source = cms.Source(
    "EmptySource",
    firstRun=cms.untracked.uint32(1),
    firstLuminosityBlock=cms.untracked.uint32(1),
    firstEvent=cms.untracked.uint32(1),
    numberEventsInLuminosityBlock=cms.untracked.uint32(1000),
    numberEventsInRun=cms.untracked.uint32(1000000000),
)
process.options = cms.untracked.PSet(
    numberOfThreads=cms.untracked.uint32(8),
    numberOfStreams=cms.untracked.uint32(0),
)

process.maxEvents = cms.untracked.PSet(input=cms.untracked.int32(-1))


# Dummy output declaration. CRAB uses this to discover the EDM output which will actually be produced by run_FullRECO.sh.
process.RECOoutput = cms.OutputModule(
    "PoolOutputModule",
    fileName=cms.untracked.string("RECO.root"),
    outputCommands=cms.untracked.vstring("keep *"),
    dataset=cms.untracked.PSet(
        dataTier=cms.untracked.string("AODSIM"),
        filterName=cms.untracked.string(""),
    ),
)
process.RECOoutput_step = cms.EndPath(process.RECOoutput)
