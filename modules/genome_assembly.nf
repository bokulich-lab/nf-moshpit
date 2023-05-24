process ASSEMBLE_METASPADES {
    conda params.condaEnvPath
    cpus params.genome_assembly.cpus
    storeDir params.storeDir
    time params.genome_assembly.time

    input:
    path reads_file

    output:
    path "contigs.qza" 

    script:
    """
    qiime assembly assemble-spades \
      --verbose \
      --i-seqs ${reads_file} \
      --p-meta --p-threads ${task.cpus} \
      --o-contigs "contigs.qza" 
    """
}

process ASSEMBLE_MEGAHIT {
    conda params.condaEnvPath
    cpus params.genome_assembly.cpus
    clusterOptions params.genome_assembly.clusterOptions
    storeDir params.storeDir
    time params.genome_assembly.time

    input:
    file reads_file

    output:
    path "contigs.qza" 

    script:
    """
    qiime assembly assemble-megahit \
      --verbose \
      --i-seqs ${reads_file} \
      --p-presets meta-sensitive \
      --p-num-cpu-threads ${task.cpus} \
      --o-contigs "contigs.qza" 
    """
}

process EVALUATE_CONTIGS {
    conda params.condaEnvPath
    cpus params.assembly_qc.cpus
    storeDir params.storeDir
    time { params.assembly_qc.time * task.attempt }
    errorStrategy "retry"
    maxRetries 3
    module "eth_proxy"

    input:
    path contigs_file
    path reads_file

    output:
    path "contigs.qzv" 
    
    script:
    if (params.assembly_qc.useReads)
      """
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --i-contigs ${contigs_file} \
        --i-reads ${reads_file} \
        --p-threads ${task.cpus} \
        --o-visualization "contigs.qzv" 
      """
    else
      """
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --i-contigs ${contigs_file} \
        --p-threads ${task.cpus} \
        --o-visualization "contigs.qzv" 
      """
}

process INDEX_CONTIGS {
    conda params.condaEnvPath
    cpus params.contig_indexing.cpus
    storeDir params.storeDir
    time params.contig_indexing.time

    input:
    path contigs_file

    output:
    path "contigs-index.qza"

    script:
    """
    qiime assembly index-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-contigs ${contigs_file} \
      --o-index "contigs-index.qza"
    """
}

process MAP_READS_TO_CONTIGS {
    conda params.condaEnvPath
    cpus params.read_mapping.cpus
    storeDir params.storeDir
    time params.read_mapping.time

    input:
    path index_file
    path reads_file

    output:
    path "contigs-mapped.qza"

    script:
    """
    qiime assembly map-reads-to-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-indexed-contigs ${index_file} \
      --i-reads ${reads_file} \
      --o-alignment-map "contigs-mapped.qza"
    """
}
