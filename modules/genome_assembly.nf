process ASSEMBLE_METASPADES {
    label "genomeAssembly"
    storeDir params.storeDir
    
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
    label "genomeAssembly"
    cpus 1
    memory 1.GB
    time params.genomeAssembly.time
    storeDir params.storeDir
    
    input:
    file reads_file
    path q2Cache

    output:
    path "contigs" 

    script:
    """
    python ${projectDir}/../scripts/generate_toml.py \
      -t ${projectDir}/../conf/parallel.template.toml \
      -o parallel.toml \
      -m '${params.genomeAssembly.memory}' \
      -c ${params.genomeAssembly.cpus} \
      -T "${params.genomeAssembly.time}" \
      -n 1 \
      -b ${params.genomeAssembly.blocks} \
      -w "${params.genomeAssembly.workerInit}"

    cat parallel.toml

    qiime assembly assemble-megahit \
      --verbose \
      --i-seqs ${params.q2cacheDir}:${reads_file} \
      --p-presets ${params.genome_assembly.megahit.presets} \
      --p-k-list ${params.genome_assembly.megahit.kList} \
      --p-min-contig-len ${params.genome_assembly.megahit.minContigLen} \
      --p-num-cpu-threads ${task.cpus} \
      --o-contigs "${params.q2cacheDir}:contigs" \
      --no-recycle \
      --parallel-config parallel.toml \
      --use-cache ${params.q2cacheDir} \
      ${params.genome_assembly.megahit.additionalFlags} \
      && touch contigs
    """
}

process EVALUATE_CONTIGS {
    label "contigEvaluation"
    label "needsInternet"
    storeDir params.storeDir
    errorStrategy "retry"
    maxRetries 3

    input:
    path contigs_file
    path reads_file
    path q2Cache

    output:
    path "contigs.qzv"
    path "quast_results_table"
    path "quast_reference_genomes"
    
    script:
    if (params.assembly_qc.useReads)
      """
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --p-threads ${task.cpus} \
        --i-contigs ${params.q2cacheDir}:${contigs_file} \
        --i-reads ${params.q2cacheDir}:${reads_file} \
        --o-visualization "contigs.qzv" \
        --o-results-table "${params.q2cacheDir}:quast_results_table" \
        --o-reference-genomes "${params.q2cacheDir}:quast_reference_genomes" \
      && touch quast_results_table \
      && touch quast_reference_genomes
      """
    else
      """
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --p-threads ${task.cpus} \
        --i-contigs ${params.q2cacheDir}:${contigs_file} \
        --o-visualization "contigs.qzv" \
        --o-results-table "${params.q2cacheDir}:quast_results_table" \
        --o-reference-genomes "${params.q2cacheDir}:quast_reference_genomes" \
      && touch quast_results_table \
      && touch quast_reference_genomes
      """
}

process INDEX_CONTIGS {
    label "indexing"
    cpus 1
    memory 1.GB
    time params.indexing.time
    storeDir params.storeDir
    
    input:
    path contigs_file
    path q2Cache

    output:
    path "contigs_index"

    script:
    """
    python ${projectDir}/../scripts/generate_toml.py \
      -t ${projectDir}/../conf/parallel.template.toml \
      -o parallel.toml \
      -m '${params.indexing.memory}' \
      -c ${params.indexing.cpus} \
      -T ${params.indexing.time} \
      -n 1 \
      -b ${params.indexing.blocks} \
      -w "${params.indexing.workerInit}"
    
    cat parallel.toml

    qiime assembly index-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-contigs ${params.q2cacheDir}:${contigs_file} \
      --o-index ${params.q2cacheDir}:contigs_index \
      --no-recycle \
      --parallel-config parallel.toml \
      --use-cache ${params.q2cacheDir} \
    && touch contigs_index
    """
}

process MAP_READS_TO_CONTIGS {
    label "readMapping"
    cpus 1
    memory 1.GB
    time params.readMapping.time
    storeDir params.storeDir
    errorStrategy { task.exitStatus == 137 ? 'retry' : 'terminate' } 
    maxRetries 3 

    input:
    path index_file
    path reads_file
    path q2Cache

    output:
    path "reads_to_contigs"

    script:
    """
    python ${projectDir}/../scripts/generate_toml.py \
      -t ${projectDir}/../conf/parallel.template.toml \
      -o parallel.toml \
      -m '${params.readMapping.memory}' \
      -c ${params.readMapping.cpus} \
      -T ${params.readMapping.time} \
      -n 1 \
      -b ${params.readMapping.blocks} \
      -w "${params.readMapping.workerInit}"

    cat parallel.toml

    qiime assembly map-reads \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-index ${params.q2cacheDir}:${index_file} \
      --i-reads ${params.q2cacheDir}:${reads_file} \
      --o-alignment-map "${params.q2cacheDir}:reads_to_contigs" \
      --no-recycle \
      --parallel-config parallel.toml \
      --use-cache ${params.q2cacheDir} \
    && touch reads_to_contigs
    """
}
