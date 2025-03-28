process ASSEMBLE_METASPADES {
    label "genomeAssembly"
    errorStrategy 'retry'
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(reads_file)

    output:
    tuple val(sample_id), path(key)

    script:
    q2cacheDir = "${params.q2cacheDir}/${sample_id}"
    key = "${params.runId}_contigs_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime assembly assemble-spades \
      --verbose \
      --i-seqs ${q2cacheDir}:${reads_file} \
      --p-threads ${task.cpus} \
      --p-k ${params.genome_assembly.spades.k} \
      --p-debug ${params.genome_assembly.spades.debug} \
      --p-cov-cutoff ${params.genome_assembly.spades.covCutoff} \
      --o-contigs "${q2cacheDir}:${key}" \
      ${params.genome_assembly.spades.additionalFlags} \
    && touch ${key}
    """
}

process ASSEMBLE_MEGAHIT {
    label "genomeAssembly"
    errorStrategy 'retry'
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(reads_file)

    output:
    tuple val(sample_id), path(key)

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    key = "${params.runId}_contigs_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime assembly assemble-megahit \
      --verbose \
      --i-seqs ${q2cacheDir}:${reads_file} \
      --p-presets ${params.genome_assembly.megahit.presets} \
      --p-k-list ${params.genome_assembly.megahit.kList} \
      --p-min-contig-len ${params.genome_assembly.megahit.minContigLen} \
      --p-num-cpu-threads ${task.cpus} \
      --no-recycle \
      --o-contigs "${q2cacheDir}:${key}" \
      ${params.genome_assembly.megahit.additionalFlags} \
    && touch ${key}
    """
}

process EVALUATE_CONTIGS {
    label "contigEvaluation"
    label "needsInternet"
    publishDir params.publishDir, mode: 'copy', pattern: '*-contigs.qzv'
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
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --p-threads ${task.cpus} \
        --i-contigs ${params.q2cacheDir}:${contigs_file} \
        --i-mapped-reads ${params.q2cacheDir}:${reads_file} \
        --o-visualization "${params.runId}-contigs.qzv" \
        --o-results-table "${params.q2cacheDir}:${params.runId}_quast_results_table" \
        --o-reference-genomes "${params.q2cacheDir}:${params.runId}_quast_reference_genomes" \
      && touch ${params.runId}_quast_results_table \
      && touch ${params.runId}_quast_reference_genomes
      """
    } else {
      """
      qiime assembly evaluate-contigs \
        --verbose \
        --p-min-contig 100 \
        --p-threads ${task.cpus} \
        --i-contigs ${params.q2cacheDir}:${contigs_file} \
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
    errorStrategy 'retry'
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(contigs_file)

    output:
    tuple val(sample_id), path(key)

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    key = "${params.runId}_contigs_index_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime assembly index-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --no-recycle \
      --i-contigs ${q2cacheDir}:${contigs_file} \
      --o-index ${q2cacheDir}:${key} \
    && touch ${key}
    """
}

process MAP_READS_TO_CONTIGS {
    label "readMapping"
    // errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'terminate' } 
    errorStrategy 'retry'
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"

    input:
    tuple val(sample_id), path(index_file), path(reads_file)

    output:
    tuple val(sample_id), path(key)

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    key = "${params.runId}_reads_to_contigs_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime assembly map-reads \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --no-recycle \
      --i-index ${q2cacheDir}:${index_file} \
      --i-reads ${q2cacheDir}:${reads_file} \
      --o-alignment-map "${q2cacheDir}:${key}" \
    && touch ${key}
    """
}

process FILTER_CONTIGS {
    errorStrategy { task.exitStatus == 125 ? 'ignore' : 'retry' }
    cpus 1
    memory 1.GB
    time { 1.h * task.attempt }
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(contigs_file)

    output:
    tuple val(sample_id), path(key)

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    key = "${params.runId}_contigs_filtered_partitioned_${sample_id}"
    removeEmpty_flag = params.genome_assembly.filtering.removeEmpty ? "--p-remove-empty True" : ""
    """
    echo Processing sample ${sample_id}

    set +e
    qiime assembly filter-contigs \
      --verbose \
      --p-length-threshold ${params.genome_assembly.filtering.lengthThreshold} \
      ${removeEmpty_flag} \
      --i-contigs ${q2cacheDir}:${contigs_file} \
      --o-filtered-contigs ${q2cacheDir}:${key} > output.txt 2> error.txt

    qiime_exit_code=\$?
    echo "QIIME exit code: \$qiime_exit_code"
    set -e

    cat output.txt >> .command.out
    cat error.txt >> .command.err

    if [ \$qiime_exit_code -eq 0 ]; then
      count=\$(ls ${q2cacheDir}/keys/ | grep ${key} | wc -l)
      if [ "\$count" -eq 1 ]; then
        touch ${key}
      else
        echo "Some of the required keys are missing in the cache."
        exit 1
      fi
    fi

    if grep -q "No samples remain after filtering" output.txt || grep -q "No samples remain after filtering" error.txt; then
      echo "All contigs were removed from this sample - the output was empty."
      exit 125
    elif grep -q "Already unlocked" output.txt || grep -q "Already unlocked" error.txt; then
      echo "Already unlocked error - please investigate the full log."

      count=\$(ls ${q2cacheDir}/keys/ | grep ${key} | wc -l)
      if [ "\$count" -eq 1 ]; then
        touch ${key}
      else
        echo "Some of the required keys are missing in the cache."
        exit 1
      fi

      echo "This error will be ignored since all the required keys are present in the cache."
      qiime_exit_code=0
    fi

    exit \$qiime_exit_code
    """
}
