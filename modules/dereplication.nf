process CALCULATE_MINHASHES {
    label "dereplication"

    input:
    path bins_file
    path q2_cache

    output:
    path "${params.runId}_mags_minhash"

    script:
    """
    qiime sourmash compute \
      --verbose \
      --p-ksizes ${params.dereplication.sourmash.ksizes} \
      --p-scaled ${params.dereplication.sourmash.scaled} \
      --p-track-abundance ${params.dereplication.sourmash.trackAbundance} \
      --i-sequence-file ${params.q2cacheDir}:${bins_file} \
      --o-min-hash-signature "${params.q2cacheDir}:${params.runId}_mags_minhash" \
    && touch ${params.runId}_mags_minhash
    """
}

process COMPARE_MINHASHES {
    label "dereplication"

    input:
    path hashes_file
    path q2_cache

    output:
    path "${params.runId}_mags_dist_matrix"

    script:
    ignore_abundance = params.dereplication.sourmash.trackAbundance ? false : true
    """
    qiime sourmash compare \
      --verbose \
      --p-ksize ${params.dereplication.sourmash.ksizes} \
      --p-ignore-abundance ${ignore_abundance} \
      --i-min-hash-signature ${params.q2cacheDir}:${hashes_file} \
      --o-compare-output "${params.q2cacheDir}:${params.runId}_mags_dist_matrix" \
    && touch ${params.runId}_mags_dist_matrix
    """
}

process DEREPLICATE_MAGS {
    label "dereplication"

    input:
    path bins_file
    path distance_matrix
    path q2_cache

    output:
    path "${params.runId}_mags_dereplicated", emit: bins_derep
    path "${params.runId}_mags_pa_table", emit: feature_table

    script:
    """
    qiime moshpit dereplicate-mags \
      --verbose \
      --p-threshold ${params.dereplication.threshold} \
      --i-mags ${params.q2cacheDir}:${bins_file} \
      --i-distance-matrix ${params.q2cacheDir}:${distance_matrix} \
      --o-dereplicated-mags "${params.q2cacheDir}:${params.runId}_mags_dereplicated" \
      --o-feature-table "${params.q2cacheDir}:${params.runId}_mags_pa_table" \
    && touch ${params.runId}_mags_dereplicated \
    && touch ${params.runId}_mags_pa_table
    """
}
