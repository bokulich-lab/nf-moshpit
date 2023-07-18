# moshpit-nf

This repository contains the Nextflow workflow for shotgun 
metagenome analysis using QIIME 2.

There are multiple ways to provide the data to the workflow:
- provide reads directly (`params.inputReads`)
- provide a list of SRA accession IDs to be fetched by [q2-fondue](https://github.com/bokulich-lab/q2-fondue) (`params.fondue.filesAccessionIds`)
- simulate reads/samples from exisitng genomes (`params.read_simulation.sampleGenomes`)
- simulate reads/samples from genomes fetched from NCBI (the workflow defaults to this option if none of the params above were specified)

Workflow configuration happens through the [nextflow.config](workflows/nextflow.config) file. Currently, the workflow is optimized to be executed using the `slurm` executor using `Singularity` containers.

## Requirements
This workflow makes use of som environment variables that are being set in the context of the Euler HPC cluster - please set those in your bashrc (or zshrc) file:
- `$WORK`: `/cluster/<group name>/<user name>`
- `$SCRATCH`: `/cluster/scratch/<user name>`

You need to create the following directories, if they do not yet exist:
- `$WORK` (see above)
- `$WORK/tmp`
- `$SCRATCH/tmp` (this will be the temporary directory used by Singularity)
- `$SCRATCH/tmp_home` (this will be mapped to `/home/qiime2` inside the Singularity container)
The work directory will be mounted in the Singularity container, so if you need to make any files available to the workflow, you should put them there. If you decide to place them elsewhere, remember to mount those paths as additional volumes in the container by appending more flags using the `params.additionalRunOptionsSingularity` option. 

> Please do not remove any of the flags included in the `additionalRunOptionsSingularity` param in the configuration - they are all required to make the _Slurm+Singularity+QIIME2_ work together!

## Configuration details
Some of the most useful configuration parameters are explained below:
| Parameter | Meaning | Singularity | Docker | Conda |
| --------- | ------- | ----------- | ------ | ----- |
| params.condaEnvPath | Location of the conda environment | - | - | X |
| params.imageTag | Location of the image for the containers | X | X | - |
| params.email | Your e-mail address - only needed when using q2-fondue | X | X | X |
| params.executor | Name of the executor to be used. Only Slurm/local are supported at the moment. | X | X | X |
| params.storeDir | Directory where all the results will be published. | X | X | X |
| params.traceDir | Directory where Nexftlow trace/report files will be saved. | X | X | X |
| params.tempDir | Temporary directory to be used by Singularity/Docker. | X | X | - |
| params.additionalRunOptionsSingularity | Additional flags to be passed to Singularity containers. | X | - | - |
| params.additionalRunOptionsDocker | Additional flags to be passed to Docker containers. | - | X | - |
| params.inputReads | Path to the QZA file containing input reads. Needs to be accessible within the containers, if used. | X | X | X |

## Usage
To use the main workflow:
1. navigate to the `workflows` directory
2. execute the workflow, adjusting the required params (also, see the config file), e.g.:
    ```shell
    nextflow -C nextflow.config run moshpit.nf \
        -entry MOSHPIT \
        -profile singularity \
        -work-dir $WORK/_data/outputs/work
    ```
