process ASSEMBLE_METASPADES {
    conda params.condaEnvPath
    cpus params.genome_assembly.cpus
    storeDir params.storeDir
    time params.genome_assembly.time
    clusterOptions "--mem-per-cpu=${params.genome_assembly.memoryPerCPU} ${params.genome_assembly.clusterOptions}"

    input:
    path reads_file
    path q2Cache

    output:
    path "contigs" 

    script:
    """
    qiime assembly assemble-spades \
      --verbose \
      --i-seqs ${params.q2cacheDir}:${reads_file} \
      --p-threads ${task.cpus} \
      --p-k ${params.genome_assembly.spades.k} \
      --p-debug ${params.genome_assembly.spades.debug} \
      --p-cov-cutoff ${params.genome_assembly.spades.covCutoff} \
      --o-contigs "${params.q2cacheDir}:contigs" \
      ${params.genome_assembly.spades.additionalFlags} \
    && touch contigs
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
    path q2Cache

    output:
    path "contigs" 

    script:
    """
    qiime assembly assemble-megahit \
      --verbose \
      --i-seqs ${params.q2cacheDir}:${reads_file} \
      --p-presets ${params.genome_assembly.megahit.presets} \
      --p-k-list ${params.genome_assembly.megahit.kList} \
      --p-min-contig-len ${params.genome_assembly.megahit.minContigLen} \
      --p-num-cpu-threads ${task.cpus} \
      --o-contigs "${params.q2cacheDir}:contigs" \
      ${params.genome_assembly.megahit.additionalFlags} \
      && touch contigs
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
    path q2Cache

    output:
    path "contigs.qzv" 
    
    script:
    if (params.assembly_qc.useReads)
      """
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --i-contigs ${params.q2cacheDir}:${contigs_file} \
        --i-reads ${params.q2cacheDir}:${reads_file} \
        --p-threads ${task.cpus} \
        --o-visualization "contigs.qzv" 
      """
    else
      """
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --i-contigs ${params.q2cacheDir}:${contigs_file} \
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
    path q2Cache

    output:
    path "contigs_index"

    script:
    """
    qiime assembly index-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-contigs ${params.q2cacheDir}:${contigs_file} \
      --o-index ${params.q2cacheDir}:contigs_index \
    && touch contigs_index
    """
}

process MAP_READS_TO_CONTIGS {
    conda params.condaEnvPath
    cpus params.read_mapping.cpus
    storeDir params.storeDir
    time params.read_mapping.time
    clusterOptions "--mem-per-cpu=${params.read_mapping.memoryPerCPU.substring(0, params.read_mapping.memoryPerCPU.size() - 2).toInteger() * task.attempt}${params.read_mapping.memoryPerCPU.substring(params.read_mapping.memoryPerCPU.size() - 2)} ${params.read_mapping.clusterOptions}"
    errorStrategy { task.exitStatus == 137 ? 'retry' : 'terminate' } 
    maxRetries 3 

    input:
    path index_file
    path reads_file
    path q2Cache

    output:
    path "contigs_mapped"

    script:
    """
    qiime assembly map-reads-to-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-indexed-contigs ${params.q2cacheDir}:${index_file} \
      --i-reads ${params.q2cacheDir}:${reads_file} \
      --o-alignment-map "${params.q2cacheDir}:contigs_mapped" \
    && touch contigs_mapped
    """
}
