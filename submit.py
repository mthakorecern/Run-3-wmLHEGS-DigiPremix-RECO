#!/usr/bin/env python3

import argparse
import csv
import os
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
CMSSW_SRC = HERE.parent
BASE_DIR = CMSSW_SRC.parents[1]
DEFAULT_CSV = BASE_DIR / "campaign" / "campaign.csv"
GENPROD_DIR = CMSSW_SRC / "Configuration" / "GenProduction" / "python"
NTHREADS = 8


def require_environment():
    if os.environ.get("CMSSW_VERSION") != "CMSSW_14_0_18":
        raise RuntimeError("Run cmsenv inside CMSSW_14_0_18 first.")
    if shutil.which("scram") is None:
        raise RuntimeError("Missing command: scram")
    try:
        import CRABAPI.RawCommand
    except ImportError as exc:
        raise RuntimeError(
            "CRAB API is unavailable. " "Run crab-setup.sh before submitting."
        ) from exc


def read_csv(path):
    rows = {}
    with Path(path).open() as handle:
        for row in csv.DictReader(handle):
            mass = int(row["Mass"])
            rows[mass] = row
    if not rows:
        raise RuntimeError(f"No campaign entries found in {path}")
    return rows


def select_masses(
    rows,
    requested,
):
    if not requested:
        return sorted(rows)
    missing = [mass for mass in requested if mass not in rows]
    if missing:
        raise RuntimeError(
            "Masses missing from campaign CSV: "
            + ", ".join(
                map(
                    str,
                    missing,
                )
            )
        )
    return sorted(set(requested))


def install_fragments(
    rows,
    masses,
):
    GENPROD_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )
    for mass in masses:
        row = rows[mass]
        source = Path(row["Pythia fragment path"]).resolve()
        if not source.is_file():
            raise FileNotFoundError(f"Pythia fragment not found: {source}")
        dataset_name = row["Dataset Name"]
        destination = GENPROD_DIR / f"{dataset_name}.py"
        shutil.copy2(
            source,
            destination,
        )
        print(f"Installed M={mass}: " f"{destination}")


def build_cmssw():
    print()
    print(f"+ scram b -j {NTHREADS}")
    subprocess.run(
        [
            "scram",
            "b",
            "-j",
            str(NTHREADS),
        ],
        cwd=CMSSW_SRC,
        check=True,
    )


def submit_mass(
    row,
    events_per_job,
    njobs,
    out_lfn_dir_base,
    storage_site,
):
    from CRABAPI.RawCommand import crabCommand
    from crabConfig import make_config

    mass = int(row["Mass"])
    dataset_name = row["Dataset Name"]
    fragment_module = dataset_name
    request_name = f"{row['CRAB Request Name']}_RECO"
    cfg = make_config()

    cfg.General.requestName = request_name
    cfg.JobType.scriptArgs = [
        f"datasetName={dataset_name}",
        f"fragmentModule={fragment_module}",
    ]
    cfg.Data.unitsPerJob = events_per_job
    cfg.Data.totalUnits = events_per_job * njobs
    cfg.Data.outputPrimaryDataset = dataset_name
    cfg.Data.outLFNDirBase = out_lfn_dir_base
    cfg.Site.storageSite = storage_site

    print(f"Submitting FullRECO M={mass}")
    print(f"Request name : {request_name}")
    print(f"Dataset      : {dataset_name}")
    print(f"Events/job   : {events_per_job}")
    print(f"Jobs         : {njobs}")
    print(f"Total events : " f"{events_per_job * njobs}")
    print(f"Output LFN   : {out_lfn_dir_base}")
    print(f"Storage site : {storage_site}")
    print()
    crabCommand(
        "submit",
        config=cfg,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--csv",
        default=str(DEFAULT_CSV),
    )
    parser.add_argument(
        "--masses",
        nargs="+",
        type=int,
    )
    parser.add_argument(
        "--events-per-job",
        type=int,
        default=100,
    )
    parser.add_argument(
        "--njobs",
        type=int,
        default=1000,
    )
    parser.add_argument(
        "--out-lfn-dir-base",
        required=True,
        help=("Example: " "/store/user/mithakor/" "SignalProduction/Run3Summer24"),
    )
    parser.add_argument(
        "--storage-site",
        default="T2_US_Wisconsin",
    )
    args = parser.parse_args()
    require_environment()
    rows = read_csv(args.csv)
    masses = select_masses(
        rows,
        args.masses,
    )
    install_fragments(
        rows,
        masses,
    )
    build_cmssw()
    for mass in masses:
        submit_mass(
            row=rows[mass],
            events_per_job=(args.events_per_job),
            njobs=(args.njobs),
            out_lfn_dir_base=(args.out_lfn_dir_base),
            storage_site=(args.storage_site),
        )


if __name__ == "__main__":
    main()
