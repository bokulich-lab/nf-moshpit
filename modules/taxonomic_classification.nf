process CLASSIFY_KRAKEN2 {
    conda params.condaEnvPath
    cpus params.taxonomic_classification.cpus
    clusterOptions "--mem-per-cpu=${params.taxonomic_classification.memoryPerCPU} ${params.taxonomic_classification.clusterOptions}"
    storeDir params.storeDir
    time params.taxonomic_classification.time
    errorStrategy "retry"
    maxRetries 3

    input:
    path input_file
    val input_type
    path q2Cache

    output:
    path reports, emit: reports
    path hits, emit: hits

    script:
    if (input_type == "mags") {
        reports = "kraken-reports-mags.qza"
        hits = "kraken-outputs-mags.qza"
    } else if (input_type == "reads") {
        reports = "kraken-reports-reads.qza"
        hits = "kraken-outputs-reads.qza"
        if (params.q2cacheDir != "") {
          input_file = "${params.q2cacheDir}:${input_file}"
        }
    }
    threads = 4 * params.taxonomic_classification.cpus
    """
    qiime moshpit classify-kraken2 \
      --verbose \
      --i-seqs ${input_file} \
      --i-kraken2-db ${params.taxonomic_classification.kraken2DBpath} \
      --p-threads ${threads} \
      --p-memory-mapping ${params.taxonomic_classification.kraken2MemoryMapping} \
      --o-reports ${reports} \
      --o-hits ${hits} \
      ${params.taxonomic_classification.additionalFlags}
    """
}

process ESTIMATE_BRACKEN {
    conda params.condaEnvPath
    clusterOptions "${params.taxonomic_classification.bracken.clusterOptions}"
    storeDir params.storeDir
    time params.taxonomic_classification.bracken.time
    errorStrategy "retry"
    maxRetries 3

    input:
    path kraken2_reports

    output:
    path "bracken-reports-reads.qza", emit: reports
    path "taxonomy-reads.qza", emit: taxonomy
    path "feature-table-reads.qza", emit: feature_table

    script:
    """
    qiime moshpit estimate-bracken \
      --verbose \
      --i-kraken-reports ${kraken2_reports} \
      --i-bracken-db ${params.taxonomic_classification.bracken.brackenDBpath} \
      --p-threshold ${params.taxonomic_classification.bracken.threshold} \
      --p-read-len ${params.taxonomic_classification.bracken.readLength} \
      --p-level ${params.taxonomic_classification.bracken.level} \
      --o-reports "bracken-reports-reads.qza" \
      --o-taxonomy "taxonomy-reads.qza" \
      --o-table "feature-table-reads.qza"
    """
}

process GET_KRAKEN_FEATURES {
    conda params.condaEnvPath
    storeDir params.storeDir
    time params.taxonomic_classification.feature_selection.time
    errorStrategy "retry"
    maxRetries 3

    input:
    path kraken2_reports
    path kraken2_hits
    val input_type

    output:
    path features, emit: taxonomy
    path "kraken-presence-absence.qza", emit: feature_table, optional: true

    script:
    if (input_type == "reads") {
      features = "kraken-features-reads.qza"
      """
      qiime moshpit kraken2-to-features \
        --verbose \
        --i-reports ${kraken2_reports} \
        --p-coverage-threshold ${params.taxonomic_classification.feature_selection.coverageThreshold} \
        --o-taxonomy ${features} \
        --o-table "presence-absence-features.qza"
      """
    } else {
      features = "kraken-features-mags.qza"
      """
      qiime moshpit kraken2-to-mag-features \
        --verbose \
        --i-reports ${kraken2_reports} \
        --i-hits ${kraken2_hits} \
        --p-coverage-threshold ${params.taxonomic_classification.feature_selection.coverageThreshold} \
        --o-taxonomy ${features}
      """
    }
}

process DRAW_TAXA_BARPLOT {
    conda params.condaEnvPath
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
      --i-table ${feature_table} \
      --i-taxonomy ${taxonomy} \
      --o-visualization "taxa-barplot-${name_suffix}.qzv"
    """
}
