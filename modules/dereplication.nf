process CALCULATE_MINHASHES {
    label "dereplication"
    storeDir params.storeDir

    input:
    path bins_file
    path q2_cache

    output:
    path "mags_minhash"

    script:
    """
    qiime sourmash compute \
      --verbose \
      --p-ksizes ${params.dereplication.sourmash.ksizes} \
      --p-scaled ${params.dereplication.sourmash.scaled} \
      --p-track-abundance ${params.dereplication.sourmash.trackAbundance} \
      --i-sequence-file ${params.q2cacheDir}:${bins_file} \
      --o-min-hash-signature "${params.q2cacheDir}:mags_minhash" \
    && touch mags_minhash
    """
}

process COMPARE_MINHASHES {
    label "dereplication"
    storeDir params.storeDir

    input:
    path hashes_file
    path q2_cache

    output:
    path "mags_dist_matrix"

    script:
    ignore_abundance = params.dereplication.sourmash.trackAbundance ? false : true
    """
    qiime sourmash compare \
      --verbose \
      --p-ksize ${params.dereplication.sourmash.ksizes} \
      --p-ignore-abundance ${ignore_abundance} \
      --i-min-hash-signature ${params.q2cacheDir}:${hashes_file} \
      --o-compare-output "${params.q2cacheDir}:mags_dist_matrix" \
    && touch mags_dist_matrix
    """
}

process DEREPLICATE_MAGS {
    label "dereplication"
    storeDir params.storeDir

    input:
    path bins_file
    path distance_matrix
    path q2_cache

    output:
    path "mags_dereplicated", emit: bins_derep
    path "mags_pa_table", emit: feature_table

    script:
    """
    qiime moshpit dereplicate-mags \
      --verbose \
      --p-threshold ${params.dereplication.threshold} \
      --i-mags ${params.q2cacheDir}:${bins_file} \
      --i-distance-matrix ${params.q2cacheDir}:${distance_matrix} \
      --o-dereplicated-mags "${params.q2cacheDir}:mags_dereplicated" \
      --o-feature-table "${params.q2cacheDir}:mags_pa_table" \
    && touch mags_dereplicated \
    && touch mags_pa_table
    """
}

process FILTER_MAGS {
    storeDir params.storeDir
    cpus 1
    memory 1.GB
    time { 20.min * task.attempt }
    maxRetries 3

    input:
    path bins_file
    path metadata_file
    val filtering_axis
    path q2_cache

    output:
    path "mags_filtered", emit: mags_filtered

    script:
    """
    qiime moshpit filter-mags \
      --verbose \
      --p-where ${params.dereplication.filtering.condition}" \
      --p-exclude-ids ${params.dereplication.filtering.exclude_ids}" \
      --p-on ${filtering_axis} \
      --m-metadata-file ${params.q2cacheDir}:${metadata_file} \
      --i-mags ${params.q2cacheDir}:${bins_file} \
      --o-filtered-mags "${params.q2cacheDir}:mags_filtered" \
    && touch mags_filtered
    """
}
