process INDEX_DEREP_MAGS {
    label "indexing"
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'

    input:
    path(mags_derep_file)
    path q2Cache

    output:
    path(key)

    script:
    key = "${params.runId}_mags_derep_index"
    """
    qiime assembly index-derep-mags \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-mags ${params.q2cacheDir}:${mags_derep_file} \
      --o-index ${params.q2cacheDir}:${key} \
    && touch ${key}
    """
}

process MAP_READS_TO_DEREP_MAGS {
    label "readMapping"
    errorStrategy 'retry'
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${_id}"

    input:
    tuple val(_id), path(reads_file), path(index_file)
    path q2Cache

    output:
    tuple val(_id), path(key)

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
    key = "${params.runId}_reads_to_derep_mags_partitioned_${_id}"
    """
    echo Processing sample ${_id}
    qiime assembly map-reads \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-index ${params.q2cacheDir}:${index_file} \
      --i-reads ${q2cacheDir}:${reads_file} \
      --o-alignment-map "${q2cacheDir}:${key}" \
    && touch ${key}
    """
}

process GET_GENOME_LENGTHS {
    cpus 1
    memory 1.GB
    time { 20.min * task.attempt }
    maxRetries 3
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'

    input:
    path mags_derep_file
    path q2Cache

    output:
    path key

    script:
    key = "${params.runId}_mags_derep_lengths"
    """
    qiime annotate get-feature-lengths \
      --verbose \
      --i-features ${params.q2cacheDir}:${mags_derep_file} \
      --o-lengths ${params.q2cacheDir}:${key} \
    && touch ${key}
    """
}

process ESTIMATE_MAG_ABUNDANCE {
    label "abundanceEstimation"
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'

    input:
    path mags_derep_index_file
    path mags_derep_lengths_file
    path q2Cache

    output:
    path key

    script:
    key = "${params.runId}_mags_derep_ft"
    """
    qiime annotate estimate-mag-abundance \
      --verbose \
      --p-metric ${params.mag_abundance.metric} \
      --p-min-mapq ${params.mag_abundance.min_mapq} \
      --p-min-query-len ${params.mag_abundance.min_query_len} \
      --p-min-base-quality ${params.mag_abundance.min_base_quality} \
      --p-threads ${task.cpus} \
      --i-maps ${params.q2cacheDir}:${mags_derep_index_file} \
      --i-mag-lengths ${params.q2cacheDir}:${mags_derep_lengths_file} \
      --o-abundances ${params.q2cacheDir}:${key} \
    && touch ${key}
    """
}
