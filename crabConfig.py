from pathlib import Path
from CRABClient.UserUtilities import config

HERE = Path(__file__).resolve().parent


def make_config():
    cfg = config()
    cfg.General.workArea = str(HERE / "crab_projects")
    cfg.General.transferOutputs = True
    cfg.General.transferLogs = False
    cfg.General.instance = "prod"
    cfg.JobType.pluginName = "PrivateMC"
    cfg.JobType.psetName = str(HERE / "bookkeeping_cfg.py")
    cfg.JobType.scriptExe = str(HERE / "run_FullRECO.sh")
    cfg.JobType.numCores = 8
    cfg.JobType.maxMemoryMB = 16000
    cfg.JobType.maxJobRuntimeMin = 90
    cfg.Data.splitting = "EventBased"
    cfg.Data.publication = True
    cfg.Data.outputDatasetTag = "Private_Run3Summer24_RECO"
    return cfg
