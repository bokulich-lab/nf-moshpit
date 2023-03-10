process FETCH_GENOMES {
    conda params.condaEnvPath
    storeDir params.storeDir

    output:
    file params.read_simulation.sampleGenomes

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

    input:
    path genomes

    output:
    path "paired-end.qza", emit: reads
    path "output_genomes.qza", emit: genomes
    path "output_abundances.qza", emit: abundances

    """
    qiime assembly generate-reads \
      --i-genomes ${genomes} \
      --p-sample-names ${params.read_simulation.sampleNames} \
      --p-cpus ${task.cpus} \
      --p-n-genomes ${params.read_simulation.nGenomes} \
      --p-n-reads ${params.read_simulation.readCount} --p-seed 42 \
      --o-reads "paired-end.qza" \
      --o-template-genomes output_genomes.qza \
      --o-abundances output_abundances.qza
    """
}

process FETCH_SEQS {
    conda params.condaEnvPath
    cpus params.fondue.cpus
    storeDir params.storeDir
    module "eth_proxy"

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
