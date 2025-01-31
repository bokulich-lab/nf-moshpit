process CLASSIFY_KRAKEN2 {
    label "taxonomicClassification"
    storeDir params.storeDir
    scratch true
    tag "${_id}"

    errorStrategy "retry"
    maxRetries 3

    input:
    tuple val(_id), path(input_file)
    path kraken2_db
    val input_type
    path q2_cache

    output:
    tuple val(_id), path(reports_key), emit: reports
    tuple val(_id), path(hits_key), emit: hits

    script:
    if (input_type == "mags") {
        reports_key = "${params.runId}_kraken_reports_mags_partitioned_${_id}"
        hits_key = "${params.runId}_kraken_outputs_mags_partitioned_${_id}"
    } else if (input_type == "mags-derep") {
        reports_key = "${params.runId}_kraken_reports_mags_derep"
        hits_key = "${params.runId}_kraken_outputs_mags_derep"
    } else if (input_type == "reads") {
        reports_key = "${params.runId}_kraken_reports_reads_partitioned_${_id}"
        hits_key = "${params.runId}_kraken_outputs_reads_partitioned_${_id}"
    } else if (input_type == "contigs") {
        reports_key = "${params.runId}_kraken_reports_contigs_partitioned_${_id}"
        hits_key = "${params.runId}_kraken_outputs_contigs_partitioned_${_id}"
    }
    threads = 4 * task.cpus
    """
    echo Processing sample ${_id}
    qiime annotate classify-kraken2 \
      --verbose \
      --i-seqs ${params.q2cacheDir}:${input_file} \
      --i-kraken2-db ${params.taxonomic_classification.kraken2.database.cache}:${params.taxonomic_classification.kraken2.database.key} \
      --p-threads ${threads} \
      --p-memory-mapping ${params.taxonomic_classification.kraken2.memoryMapping} \
      --o-reports ${params.q2cacheDir}:${reports_key} \
      --o-hits ${params.q2cacheDir}:${hits_key} \
      ${params.taxonomic_classification.kraken2.additionalFlags} \
    && touch ${reports_key} \
    && touch ${hits_key}
    """
}

process ESTIMATE_BRACKEN {
    time { 12.h * task.attempt }
    errorStrategy "retry"
    maxRetries 3
    storeDir params.storeDir
    scratch true

    input:
    path kraken2_reports
    path bracken_db
    path q2_cache

    output:
    path "${params.runId}_bracken_reports_reads", emit: reports
    path "${params.runId}_taxonomy_reads", emit: taxonomy
    path "${params.runId}_feature_table_reads", emit: feature_table

    script:
    """
    qiime annotate estimate-bracken \
      --verbose \
      --i-kraken-reports ${params.q2cacheDir}:${kraken2_reports} \
      --i-bracken-db ${params.taxonomic_classification.bracken.database.cache}:${params.taxonomic_classification.bracken.database.key} \
      --p-threshold ${params.taxonomic_classification.bracken.threshold} \
      --p-read-len ${params.taxonomic_classification.bracken.readLength} \
      --p-level ${params.taxonomic_classification.bracken.level} \
      --o-reports ${params.q2cacheDir}:${params.runId}_bracken_reports_reads \
      --o-taxonomy "${params.q2cacheDir}:${params.runId}_taxonomy_reads" \
      --o-table "${params.q2cacheDir}:${params.runId}_feature_table_reads" \
    && touch ${params.runId}_bracken_reports_reads \
    && touch ${params.runId}_taxonomy_reads \
    && touch ${params.runId}_feature_table_reads
    """
}

process GET_KRAKEN_FEATURES {
    time { 12.h * task.attempt }
    errorStrategy "retry"
    maxRetries 3
    storeDir params.storeDir
    scratch true

    input:
    path kraken2_reports
    path kraken2_hits
    val input_type

    output:
    path features, emit: taxonomy
    path "${params.runId}_kraken_presence_absence", emit: feature_table, optional: true

    script:
    features = "${params.runId}_kraken_features_${input_type}"
    if (input_type == "reads") {
      """
      qiime annotate kraken2-to-features \
        --verbose \
        --i-reports ${params.q2cacheDir}:${kraken2_reports} \
        --p-coverage-threshold ${params.taxonomic_classification.feature_selection.coverageThreshold} \
        --o-taxonomy ${params.q2cacheDir}:${features} \
        --o-table "${params.q2cacheDir}:${params.runId}_kraken_presence_absence" \
      && touch ${features} \
      && touch ${params.runId}_kraken_presence_absence
      """
    } else {
      """
      qiime annotate kraken2-to-mag-features \
        --verbose \
        --i-reports ${params.q2cacheDir}:${kraken2_reports} \
        --i-hits ${params.q2cacheDir}:${kraken2_hits} \
        --p-coverage-threshold ${params.taxonomic_classification.feature_selection.coverageThreshold} \
        --o-taxonomy ${params.q2cacheDir}:${features} \
      && touch ${features}
      """
    }
}

process DRAW_TAXA_BARPLOT {
    publishDir params.publishDir, mode: 'copy'
    scratch true

    input:
    path feature_table
    path taxonomy
    val name_suffix

    output:
    path "${params.runId}-taxa-barplot-${name_suffix}.qzv"

    script:
    """
    qiime taxa barplot \
      --verbose \
      --i-table ${params.q2cacheDir}:${feature_table} \
      --i-taxonomy ${params.q2cacheDir}:${taxonomy} \
      --o-visualization "${params.runId}-taxa-barplot-${name_suffix}.qzv"
    """
}

process FETCH_KRAKEN2_DB {
    label "needsInternet"
    cpus 1
    memory 1.GB
    time { 1.h * task.attempt }
    maxRetries 3
    storeDir "${params.taxonomic_classification.kraken2.database.cache}/keys"
    scratch true

    input:
    path q2_cache

    output:
    path params.taxonomic_classification.kraken2.database.key, emit: kraken2_db
    path params.taxonomic_classification.bracken.database.key, emit: bracken_db

    script:
    """
    if [ -f ${params.taxonomic_classification.kraken2.database.cache}/keys/${params.taxonomic_classification.kraken2.database.key} ]; then
      echo 'Found an existing Kraken 2 database - fetching will be skipped.'
      touch ${params.taxonomic_classification.kraken2.database.key}
      touch ${params.taxonomic_classification.bracken.database.key}
      exit 0
    fi
    qiime annotate build-kraken-db \
      --verbose \
      --p-collection ${params.taxonomic_classification.kraken2.database.collection} \
      --o-kraken2-database "${params.taxonomic_classification.kraken2.database.cache}:${params.taxonomic_classification.kraken2.database.key}" \
      --o-bracken-database "${params.taxonomic_classification.bracken.database.cache}:${params.taxonomic_classification.bracken.database.key}" \
    && touch ${params.taxonomic_classification.kraken2.database.key} \
    && touch ${params.taxonomic_classification.bracken.database.key}
    """
}
