# moshpit-workflows

This repository contains a selection of Nextflow workflows for shotgun 
metagenome analysis using QIIME 2. The workflows are being updated as new 
functionality is being added to the respective QIIME plugins. 

Currently available pipelines are:
- [from-genomes](workflows/from-genomes/from-genomes-pipeline.nf): contig assembly and binning from simulated reads, given a selection of reference genomes
- [full-pipeline](workflows/full-pipeline/full-pipeline.nf): contig assembly and binning from simulated reads generated from genomes fetched given a taxon ID

To use a workflow:
1. install Nextflow by following the instructions in the [documentation](https://www.nextflow.io/)
2. navigate to the `workflows` directory
3. execute the desired workflow, adjusting the required params (see respective config files), e.g.:
    ```shell
    nextflow run full-pipeline/full-pipeline.nf --condaEnvPath "/path/to/your/conda/environment" --storeDir "~/nextflow_results" --cpus 6 -entry MetaSPAdes
    ```
