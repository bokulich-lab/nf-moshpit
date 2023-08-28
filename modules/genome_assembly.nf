process ASSEMBLE_METASPADES {
    conda params.condaEnvPath
    cpus params.genome_assembly.cpus
    storeDir params.storeDir
    time params.genome_assembly.time
    clusterOptions "--mem-per-cpu=${params.genome_assembly.memoryPerCPU} ${params.genome_assembly.clusterOptions}"

    input:
    path reads_file

    output:
    path "contigs.qza" 

    script:
    """
    qiime assembly assemble-spades \
      --verbose \
      --i-seqs ${reads_file} \
      --p-threads ${task.cpus} \
      --p-k ${params.genome_assembly.spades.k} \
      --p-debug ${params.genome_assembly.spades.debug} \
      --p-cov-cutoff ${params.genome_assembly.spades.covCutoff} \
      --o-contigs "contigs.qza" \
      ${params.genome_assembly.spades.additionalFlags}
    """
}

process ASSEMBLE_MEGAHIT {
    conda params.condaEnvPath
    cpus params.genome_assembly.cpus
    storeDir params.storeDir
    time params.genome_assembly.time
    clusterOptions "--mem-per-cpu=${params.genome_assembly.memoryPerCPU} ${params.genome_assembly.clusterOptions}"

    input:
    file reads_file

    output:
    path "contigs.qza" 

    script:
    """
    qiime assembly assemble-megahit \
      --verbose \
      --i-seqs ${reads_file} \
      --p-presets ${params.genome_assembly.megahit.presets} \
      --p-k-list ${params.genome_assembly.megahit.kList} \
      --p-min-contig-len ${params.genome_assembly.megahit.minContigLen} \
      --p-num-cpu-threads ${task.cpus} \
      --o-contigs "contigs.qza" \
      ${params.genome_assembly.megahit.additionalFlags}
    """
}

process EVALUATE_CONTIGS {
    conda params.condaEnvPath
    cpus params.assembly_qc.cpus
    storeDir params.storeDir
    time { params.assembly_qc.time * task.attempt }
    clusterOptions "--mem-per-cpu=${params.assembly_qc.memoryPerCPU} ${params.assembly_qc.clusterOptions}"
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
    clusterOptions "--mem-per-cpu=${params.contig_indexing.memoryPerCPU} ${params.contig_indexing.clusterOptions}"

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
    clusterOptions "--mem-per-cpu=${params.read_mapping.memoryPerCPU} ${params.read_mapping.clusterOptions}"

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
