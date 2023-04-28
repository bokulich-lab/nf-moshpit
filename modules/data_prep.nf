process FETCH_GENOMES {
    conda params.condaEnvPath
    storeDir params.storeDir

    output:
    path params.read_simulation.sampleGenomes

    """
    qiime rescript get-ncbi-genomes \
      --verbose \
      --p-taxon ${params.read_simulation.taxon} \
      --p-assembly-levels complete_genome \
      --p-assembly-source refseq \
      --o-genome-assemblies ${params.read_simulation.sampleGenomes} \
      --o-loci "sample-loci.qza" \
      --o-proteins "sample-proteins.qza" \
      --o-taxonomies "sample-taxonomy.qza"
    """
}

process SIMULATE_READS {
    conda params.condaEnvPath
    cpus params.read_simulation.cpus
    storeDir params.storeDir
    time params.read_simulation.time

    input:
    path genomes

    output:
    path "reads.qza", emit: reads
    path "output_genomes.qza", emit: genomes
    path "output_abundances.qza", emit: abundances

    """
    qiime assembly generate-reads \
      --verbose \
      --i-genomes ${genomes} \
      --p-sample-names ${params.read_simulation.sampleNames} \
      --p-cpus ${task.cpus} \
      --p-n-genomes ${params.read_simulation.nGenomes} \
      --p-n-reads ${params.read_simulation.readCount} \
      --p-seed ${params.read_simulation.seed} \
      --p-abundance ${params.read_simulation.abundance} \
      --p-gc-bias ${params.read_simulation.gc_bias} \
      --o-reads "reads.qza" \
      --o-template-genomes output_genomes.qza \
      --o-abundances output_abundances.qza
    """
}

process FETCH_SEQS {
    conda params.condaEnvPath
    cpus params.fondue.cpus
    storeDir params.storeDir
    module "eth_proxy"
    time params.fondue.time

    input:
    path ids

    output:
    path "single-end-seqs.qza", emit: single
    path "paired-end-seqs.qza", emit: paired
    path "failed-runs.qza", emit: failed

    """
    if [ ! -d "$HOME/.ncbi" ]; then
        mkdir $HOME/.ncbi
        printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg
    elif [ ! -f "$HOME/.ncbi/user-settings.mkfg" ]; then
        printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg
    fi

    qiime fondue get-sequences \
      --verbose \
      --i-accession-ids ${ids} \
      --p-email ${params.email} \
      --p-n-jobs ${task.cpus} \
      --o-single-reads "single-end-seqs.qza" \
      --o-paired-reads "paired-end-seqs.qza" \
      --o-failed-runs "failed-runs.qza"
    """
}

process SUBSAMPLE_READS {
    conda params.condaEnvPath
    cpus params.read_subsampling.cpus
    storeDir params.storeDir
    time params.read_subsampling.time

    input:
    path reads

    output:
    path reads_subsampled

    script:
    reads_subsampled = "reads-subsampled-${params.read_subsampling.fraction}.qza"
    if (params.read_subsampling.paired)
      """
      qiime demux subsample-paired \
        --verbose \
        --i-sequences ${reads} \
        --p-fraction ${params.read_subsampling.fraction} \
        --o-subsampled-sequences ${reads_subsampled}
      """
    else
      """
      qiime demux subsample-single \
        --verbose \
        --i-sequences ${reads} \
        --p-fraction ${params.read_subsampling.fraction} \
        --o-subsampled-sequences ${reads_subsampled}
      """
}
