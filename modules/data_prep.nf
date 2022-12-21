process FETCH_GENOMES {
    conda params.condaEnvPath
    storeDir params.storeDir

    output:
    file params.sampleGenomes

    """
    qiime rescript get-ncbi-genomes \
      --verbose \
      --p-taxon ${params.taxon} \
      --p-assembly-levels complete_genome \
      --p-assembly-source refseq \
      --o-genome-assemblies ${params.sampleGenomes} \
      --o-loci ${params.sampleLoci} \
      --o-proteins ${params.sampleProteins} \
      --o-taxonomies ${params.sampleTaxonomy}
    """
}

process SIMULATE_READS {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path genomes

    output:
    path params.filesReads, emit: reads
    path "output_genomes.qza", emit: genomes
    path "output_abundances.qza", emit: abundances

    """
    qiime assembly generate-reads \
      --i-genomes ${genomes} \
      --p-sample-names ${params.sampleNames} \
      --p-cpus ${task.cpus} \
      --p-n-genomes ${params.nGenomes} \
      --p-n-reads ${params.readCount} --p-seed 42 \
      --o-reads ${params.filesReads} \
      --o-template-genomes output_genomes.qza \
      --o-abundances output_abundances.qza
    """
}

process FETCH_SEQS {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path ids

    output:
    path params.filesSingleEndSeqs, emit: single
    path params.filesPairedEndSeqs, emit: paired
    path params.filesFailedRuns, emit: failed

    """
    qiime fondue get-sequences \
      --verbose \
      --i-accession-ids ${ids} \
      --p-email ${params.email} \
      --p-n-jobs ${task.cpus} \
      --o-single-reads ${params.filesSingleEndSeqs} \
      --o-paired-reads ${params.filesPairedEndSeqs} \
      --o-failed-runs ${params.filesFailedRuns}
    """
}
