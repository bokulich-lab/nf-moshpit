process CLASSIFY_KRAKEN2 {
    label "taxonomicClassification"
    cpus 1
    memory 1.GB
    time params.taxonomicClassification.time
    storeDir params.storeDir

    errorStrategy "retry"
    maxRetries 3

    input:
    path input_file
    path kraken2_db
    val input_type
    path q2_cache

    output:
    path reports, emit: reports
    path hits, emit: hits

    script:
    if (input_type == "mags") {
        reports = "kraken_reports_mags"
        hits = "kraken_outputs_mags"
    } else if (input_type == "reads") {
        reports = "kraken_reports_reads"
        hits = "kraken_outputs_reads"
    }
    threads = 4 * task.cpus
    """
    python ${projectDir}/../scripts/generate_toml.py \
      -t ${projectDir}/../conf/parallel.template.toml \
      -o parallel.toml \
      -m '${params.taxonomicClassification.memory}' \
      -c ${params.taxonomicClassification.cpus} \
      -T ${params.taxonomicClassification.time} \
      -n 1 \
      -b ${params.taxonomicClassification.blocks} \
      -w "${params.taxonomicClassification.workerInit}"

    cat parallel.toml

    qiime moshpit classify-kraken2 \
      --verbose \
      --i-seqs ${params.q2cacheDir}:${input_file} \
      --i-kraken2-db ${params.q2cacheDir}:${params.taxonomic_classification.kraken2DBkey} \
      --p-threads ${threads} \
      --p-memory-mapping ${params.taxonomic_classification.kraken2MemoryMapping} \
      --o-reports ${params.q2cacheDir}:${reports} \
      --o-hits ${params.q2cacheDir}:${hits} \
      --no-recycle \
      --parallel-config parallel.toml \
      --use-cache ${params.q2cacheDir} \
      ${params.taxonomic_classification.additionalFlags} \
    && touch ${reports} \
    && touch ${hits}
    """
}

process ESTIMATE_BRACKEN {
    storeDir params.storeDir
    time { 12.h * task.attempt }
    errorStrategy "retry"
    maxRetries 3

    input:
    path kraken2_reports
    path bracken_db
    path q2_cache

    output:
    path "bracken_reports_reads", emit: reports
    path "taxonomy_reads", emit: taxonomy
    path "feature_table_reads", emit: feature_table

    script:
    """
    qiime moshpit estimate-bracken \
      --verbose \
      --i-kraken-reports ${params.q2cacheDir}:${kraken2_reports} \
      --i-bracken-db ${params.q2cacheDir}:${params.taxonomic_classification.bracken.brackenDBkey} \
      --p-threshold ${params.taxonomic_classification.bracken.threshold} \
      --p-read-len ${params.taxonomic_classification.bracken.readLength} \
      --p-level ${params.taxonomic_classification.bracken.level} \
      --o-reports ${params.q2cacheDir}:bracken_reports_reads \
      --o-taxonomy "${params.q2cacheDir}:taxonomy_reads" \
      --o-table "${params.q2cacheDir}:feature_table_reads" \
    && touch bracken_reports_reads \
    && touch taxonomy_reads \
    && touch feature_table_reads
    """
}

process GET_KRAKEN_FEATURES {
    storeDir params.storeDir
    time { 12.h * task.attempt }
    errorStrategy "retry"
    maxRetries 3

    input:
    path kraken2_reports
    path kraken2_hits
    val input_type

    output:
    path features, emit: taxonomy
    path "kraken_presence_absence", emit: feature_table, optional: true

    script:
    if (input_type == "reads") {
      features = "kraken_features_reads"
      """
      qiime moshpit kraken2-to-features \
        --verbose \
        --i-reports ${params.q2cacheDir}:${kraken2_reports} \
        --p-coverage-threshold ${params.taxonomic_classification.feature_selection.coverageThreshold} \
        --o-taxonomy ${params.q2cacheDir}:${features} \
        --o-table "${params.q2cacheDir}:kraken_presence_absence" \
      && touch ${features} \
      && touch kraken_presence_absence
      """
    } else {
      features = "kraken_features_mags"
      """
      qiime moshpit kraken2-to-mag-features \
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
    storeDir params.storeDir

    input:
    path feature_table
    path taxonomy
    val name_suffix

    output:
    path "taxa-barplot-${name_suffix}.qzv"

    script:
    """
    qiime taxa barplot \
      --verbose \
      --i-table ${params.q2cacheDir}:${feature_table} \
      --i-taxonomy ${params.q2cacheDir}:${taxonomy} \
      --o-visualization "taxa-barplot-${name_suffix}.qzv"
    """
}

process FETCH_KRAKEN2_DB {
    label "needsInternet"
    cpus 1
    memory 1.GB
    time { 1.h * task.attempt }
    storeDir params.storeDir
    maxRetries 3

    input:
    path q2_cache

    output:
    path params.taxonomic_classification.kraken2DBkey, emit: kraken2_db
    path params.taxonomic_classification.bracken.brackenDBkey, emit: bracken_db

    script:
    """
    if [ -f ${params.q2cacheDir}/keys/${params.taxonomic_classification.kraken2DBkey} ]; then
      echo 'Found an existing Kraken 2 database - fetching will be skipped.'
      touch ${params.taxonomic_classification.kraken2DBkey}
      touch ${params.taxonomic_classification.bracken.brackenDBkey}
      exit 0
    fi
    qiime moshpit build-kraken-db \
      --verbose \
      --p-collection ${params.taxonomic_classification.collection} \
      --o-kraken2-database "${params.q2cacheDir}:${params.taxonomic_classification.kraken2DBkey}" \
      --o-bracken-database "${params.q2cacheDir}:${params.taxonomic_classification.bracken.brackenDBkey}" \
    && touch ${params.taxonomic_classification.kraken2DBkey} \
    && touch ${params.taxonomic_classification.bracken.brackenDBkey}
    """
}
