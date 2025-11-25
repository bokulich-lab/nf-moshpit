process CALCULATE_MINHASHES {
    label "dereplication"
    storeDir params.storeDir
    scratch true

    input:
    path bins_file
    path q2_cache

    output:
    path minhash_key

    script:
    if (params.binning.qc.busco.enabled) {
      minhash_key = "${params.runId}_mags_minhash_${params.binning.qc.busco.selectLineage}"
    } else {
      minhash_key = "${params.runId}_mags_minhash"
    }
    """
    qiime sourmash compute \
      --verbose \
      --p-ksizes ${params.dereplication.sourmash.ksizes} \
      --p-scaled ${params.dereplication.sourmash.scaled} \
      --p-track-abundance ${params.dereplication.sourmash.trackAbundance} \
      --i-sequence-file ${params.q2cacheDir}:${bins_file} \
      --o-min-hash-signature "${params.q2cacheDir}:${minhash_key}" \
    && touch ${minhash_key}
    """
}

process COMPARE_MINHASHES {
    label "dereplication"
    storeDir params.storeDir
    scratch true

    input:
    path hashes_file
    path q2_cache

    output:
    path dist_matrix_key

    script:
    ignore_abundance = params.dereplication.sourmash.trackAbundance ? false : true
    if (params.binning.qc.busco.enabled) {
      dist_matrix_key = "${params.runId}_mags_dist_matrix_${params.binning.qc.busco.selectLineage}"
    } else {
      dist_matrix_key = "${params.runId}_mags_dist_matrix"
    }
    """
    qiime sourmash compare \
      --verbose \
      --p-ksize ${params.dereplication.sourmash.ksizes} \
      --p-ignore-abundance ${ignore_abundance} \
      --i-min-hash-signature ${params.q2cacheDir}:${hashes_file} \
      --o-compare-output "${params.q2cacheDir}:${dist_matrix_key}" \
    && touch ${dist_matrix_key}
    """
}

process COMPARE_GENOMES_SKANI {
    container params.containerSkani
    label "dereplication"
    errorStrategy 'retry'
    maxRetries 3
    storeDir params.storeDir
    clusterOptions params.dereplication.skani.clusterOptions

    input:
    path bins_file
    path q2_cache

    output:
    path dist_matrix_key

    script:
    robust_flag = params.dereplication.skani.robust ? "--p-robust True" : ""
    median_flag = params.dereplication.skani.median ? "--p-median True" : ""
    faster_small_flag = params.dereplication.skani.fasterSmall ? "--p-faster-small True" : ""
    if (params.binning.qc.busco.enabled) {
      dist_matrix_key = "${params.runId}_mags_dist_matrix_${params.binning.qc.busco.selectLineage}"
    } else {
      dist_matrix_key = "${params.runId}_mags_dist_matrix"
    }
    """
    qiime skani compare-seqs \
      --verbose \
      --p-threads ${task.cpus} \
      --p-preset ${params.dereplication.skani.preset} \
      --p-marker-c ${params.dereplication.skani.markerC} \
      --o-distance-matrix "${params.q2cacheDir}:${dist_matrix_key}" \
      ${robust_flag} \
      ${median_flag} \
      ${faster_small_flag} \
      ${params.dereplication.skani.additionalFlags} \
    && touch ${dist_matrix_key}
    """
}

process DEREPLICATE_MAGS {
    label "dereplication"
    storeDir params.storeDir
    scratch true

    input:
    path bins_file
    path distance_matrix
    path q2_cache

    output:
    path bins_derep_key, emit: bins_derep
    path feature_table_key, emit: feature_table

    script:
    if (params.binning.qc.busco.enabled) {
      bins_derep_key = "${params.runId}_mags_dereplicated_${params.binning.qc.busco.selectLineage}"
      feature_table_key = "${params.runId}_mags_pa_table_${params.binning.qc.busco.selectLineage}"
    } else {
      bins_derep_key = "${params.runId}_mags_dereplicated"
      feature_table_key = "${params.runId}_mags_pa_table"
    }
    """
    qiime annotate dereplicate-mags \
      --verbose \
      --p-threshold ${params.dereplication.threshold} \
      --i-mags ${params.q2cacheDir}:${bins_file} \
      --i-distance-matrix ${params.q2cacheDir}:${distance_matrix} \
      --o-dereplicated-mags "${params.q2cacheDir}:${bins_derep_key}" \
      --o-table "${params.q2cacheDir}:${feature_table_key}" \
    && touch ${bins_derep_key} \
    && touch ${feature_table_key}
    """
}
