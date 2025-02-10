process ASSEMBLE_METASPADES {
    label "genomeAssembly"
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(reads_file)
    path q2Cache

    output:
    tuple val(sample_id), path(key)

    script:
    key = "${params.runId}_contigs_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime assembly assemble-spades \
      --verbose \
      --i-seqs ${params.q2cacheDir}:${reads_file} \
      --p-threads ${task.cpus} \
      --p-k ${params.genome_assembly.spades.k} \
      --p-debug ${params.genome_assembly.spades.debug} \
      --p-cov-cutoff ${params.genome_assembly.spades.covCutoff} \
      --o-contigs "${params.q2cacheDir}:${key}" \
      ${params.genome_assembly.spades.additionalFlags} \
    && touch ${key}
    """
}

process ASSEMBLE_MEGAHIT {
    label "genomeAssembly"
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(reads_file)
    path q2Cache

    output:
    tuple val(sample_id), path(key)

    script:
    key = "${params.runId}_contigs_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime assembly assemble-megahit \
      --verbose \
      --i-seqs ${params.q2cacheDir}:${reads_file} \
      --p-presets ${params.genome_assembly.megahit.presets} \
      --p-k-list ${params.genome_assembly.megahit.kList} \
      --p-min-contig-len ${params.genome_assembly.megahit.minContigLen} \
      --p-num-cpu-threads ${task.cpus} \
      --o-contigs "${params.q2cacheDir}:${key}" \
      --use-cache ${params.q2cacheDir} \
      ${params.genome_assembly.megahit.additionalFlags} \
      && touch ${key}
    """
}

process EVALUATE_CONTIGS {
    label "contigEvaluation"
    label "needsInternet"
    publishDir params.publishDir, mode: 'copy', pattern: 'contigs.qzv'
    errorStrategy "retry"
    maxRetries 3
    scratch true

    input:
    path contigs_file
    path reads_file
    path q2Cache

    output:
    path "${params.runId}-contigs.qzv"
    path "${params.runId}_quast_results_table"
    path "${params.runId}_quast_reference_genomes"
    
    script:
    if (params.assembly_qc.useMappedReads) {
      """
      contigs=\$(for path in ${contigs_file}; do echo "${params.q2cacheDir}:\$(basename "\$path")"; done)
      echo \$contigs
      maps=\$(for path in ${reads_file}; do echo "${params.q2cacheDir}:\$(basename "\$path")"; done)
      echo \$maps
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --p-threads ${task.cpus} \
        --i-contigs \$contigs \
        --i-mapped-reads \$maps \
        --o-visualization "${params.runId}-contigs.qzv" \
        --o-results-table "${params.q2cacheDir}:${params.runId}_quast_results_table" \
        --o-reference-genomes "${params.q2cacheDir}:${params.runId}_quast_reference_genomes" \
      && touch ${params.runId}_quast_results_table \
      && touch ${params.runId}_quast_reference_genomes
      """
    } else {
      """
      contigs=\$(for path in ${contigs_file}; do echo "${params.q2cacheDir}:\$(basename "\$path")"; done)
      echo \$contigs
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --p-threads ${task.cpus} \
        --i-contigs \$contigs \
        --o-visualization "${params.runId}-contigs.qzv" \
        --o-results-table "${params.q2cacheDir}:${params.runId}_quast_results_table" \
        --o-reference-genomes "${params.q2cacheDir}:${params.runId}_quast_reference_genomes" \
      && touch ${params.runId}_quast_results_table \
      && touch ${params.runId}_quast_reference_genomes
      """
    }
}

process INDEX_CONTIGS {
    label "indexing"
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(contigs_file)
    path q2Cache

    output:
    tuple val(sample_id), path(key)

    script:
    key = "${params.runId}_contigs_index_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime assembly index-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-contigs ${params.q2cacheDir}:${contigs_file} \
      --o-index ${params.q2cacheDir}:${key} \
      --use-cache ${params.q2cacheDir} \
    && touch ${key}
    """
}

process MAP_READS_TO_CONTIGS {
    label "readMapping"
    errorStrategy { task.exitStatus == 137 ? 'retry' : 'terminate' } 
    maxRetries 3 
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"

    input:
    tuple val(sample_id), path(index_file), path(reads_file)
    path q2Cache

    output:
    tuple val(sample_id), path(key)

    script:
    key = "${params.runId}_reads_to_contigs_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime assembly map-reads \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-index ${params.q2cacheDir}:${index_file} \
      --i-reads ${params.q2cacheDir}:${reads_file} \
      --o-alignment-map "${params.q2cacheDir}:${key}" \
      --use-cache ${params.q2cacheDir} \
    && touch ${key}
    """
}

process FILTER_CONTIGS {
    errorStrategy { task.exitStatus == 125 ? 'ignore' : 'terminate' }
    cpus 1
    memory 4.GB
    time { 1.h * task.attempt }
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(contigs_file)
    path q2Cache

    output:
    tuple val(sample_id), path(key)

    script:
    key = "${params.runId}_contigs_filtered_partitioned_${sample_id}"
    removeEmpty_flag = params.genome_assembly.filtering.removeEmpty ? "--p-remove-empty True" : ""
    """
    echo Processing sample ${sample_id}
    qiime assembly filter-contigs \
      --verbose \
      --p-length-threshold ${params.genome_assembly.filtering.lengthThreshold} \
      ${removeEmpty_flag} \
      --i-contigs ${params.q2cacheDir}:${contigs_file} \
      --o-filtered-contigs ${params.q2cacheDir}:${key} &> output.txt \
    && touch ${key}

    if grep -q "No samples remain after filtering" output.txt; then
      echo "All contigs were removed from this sample - the output was empty."
      exit 125
    else
      exit 0
    fi
    """
}
