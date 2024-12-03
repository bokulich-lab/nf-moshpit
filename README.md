# moshpit-nf

**Currently supported QIIME 2 version:** `2024.10`

**Currently supported runtimes:** `conda`

This repository contains the Nextflow workflow for shotgun metagenome analysis using QIIME 2. A working QIIME 2 metagenome conda environment 
is required to execute the action included in this workflow. Please follow the [official QIIME 2 installation instructions](https://docs.qiime2.org/2024.10/install/native/#qiime-2-metagenome-distribution) to learn how to create one.

Workflow configuration happens through several config files:
- [nextflow.config](nextflow.config): executor and runtime selection as well as all relevant directories
- [resources.config](conf/resources.config): CPU, memory and time requirements for each process
- [tools.config](conf/tools.config): remaining parameters for each process
- [conda.config](conf/conda.config): conda-specific parameters 

There are multiple ways to provide the data to the workflow (the workflow will look for the data in this order):
- provide reads directly (`params.inputReads`)
- provide a list of SRA accession IDs to be fetched by [q2-fondue](https://github.com/bokulich-lab/q2-fondue) (`params.fondue.filesAccessionIds` in the [respective config](conf/tools.config))
- simulate reads/samples from exisitng genomes (`params.read_simulation.sampleGenomes` in the [respective config](conf/tools.config))
- simulate reads/samples from genomes fetched from NCBI (the workflow defaults to this option if none of the params above were specified)

## Configuration details
Some of the most useful configuration parameters are explained below:
| Parameter | Meaning | Config file |
| --------- | ------- | ----------- |
| process.conda | Location of the conda environment | [conf/conda.config](conf/conda.config) |
| params.email | Your e-mail address - only needed when using q2-fondue | [nextflow.config](nextflow.config) |
| params.executor | Name of the executor to be used. Only Slurm/local are supported at the moment. | [nextflow.config](nextflow.config) |
| params.storeDir | Directory where all temporary results will be stored (important for ressumption). | [nextflow.config](nextflow.config) |
| params.publishDir | Directory where final results (qza and qzv) will be stored. | [nextflow.config](nextflow.config) |
| params.traceDir | Directory where Nexftlow trace/report files will be saved. | [nextflow.config](nextflow.config) |
| params.tempDir | Temporary directory to be used by Singularity/Docker. | [nextflow.config](nextflow.config) |
| params.inputReads | Path to the QZA file containing input reads. Needs to be accessible within the containers, if used. | [nextflow.config](nextflow.config) |
| params.q2cacheDir | QIIME 2 cache location - will be created if it does not exist. | [nextflow.config](nextflow.config) |
| params.q2cacheDirExists | Default workflow behaviour if cache exists: "ok" to use the exisiting cache, "error" to stop execution. | [nextflow.config](nextflow.config) |


Currently, the workflow is optimized to be executed using the `slurm` executor using `conda`. As we are leveraging the parallel execution capabilities provided by parsl/QIIME 2, working with containers is currently not supported (work in progress).

## Usage
To use the main workflow adjust all the required parameters in respective config files (particularly all the directories, as described above) and execute the following command from the main directory:
```shell
nextflow -C nextflow.config run workflows/moshpit.nf \
    -entry MOSHPIT \
    -profile slurm \
    -with-conda \
    -work-dir <path to the work directory>
```
