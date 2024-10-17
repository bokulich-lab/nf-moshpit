process INDEX_DEREP_MAGS {
    label "indexing"
    cpus params.indexing.cpus
    memory params.indexing.memory
    time params.readMapping.time
    storeDir params.storeDir

    input:
    path mags_derep_file
    path q2Cache

    output:
    path "mags_derep_index"

    script:
    """
    qiime assembly index-derep-mags \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-mags ${params.q2cacheDir}:${mags_derep_file} \
      --o-index ${params.q2cacheDir}:mags_derep_index \
    && touch mags_derep_index
    """
}

process MAP_READS_TO_DEREP_MAGS {
    label "readMapping"
    storeDir params.storeDir
    cpus 1
    memory 1.GB
    time params.readMapping.time
    errorStrategy { task.exitStatus == 137 ? 'retry' : 'terminate' }
    maxRetries 3

    input:
    path index_file
    path reads_file
    path q2Cache

    output:
    path "reads_to_derep_mags"

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
      --o-alignment-map "${params.q2cacheDir}:reads_to_derep_mags" \
      --no-recycle \
      --parallel-config parallel.toml \
      --use-cache ${params.q2cacheDir} \
    && touch reads_to_derep_mags
    """
}

process GET_GENOME_LENGTHS {
    cpus 1
    memory 1.GB
    time { 20.min * task.attempt }
    storeDir params.storeDir
    maxRetries 3

    input:
    path mags_derep_file
    path q2Cache

    output:
    path "mags_derep_lengths"

    script:
    """
    qiime moshpit get-feature-lengths \
      --verbose \
      --i-features ${params.q2cacheDir}:${mags_derep_file} \
      --o-lengths ${params.q2cacheDir}:mags_derep_lengths \
    && touch mags_derep_lengths
    """
}

process ESTIMATE_MAG_ABUNDANCE {
    label "abundanceEstimation"
    storeDir params.storeDir

    input:
    path mags_derep_index_file
    path mags_derep_lengths_file
    path q2Cache

    output:
    path "mags_derep_ft"

    script:
    """
    qiime moshpit estimate-mag-abundance \
      --verbose \
      --p-metric ${params.mag_abundance.metric} \
      --p-min-mapq ${params.mag_abundance.min_mapq} \
      --p-min-query-len ${params.mag_abundance.min_query_len} \
      --p-min-base-quality ${params.mag_abundance.min_base_quality} \
      --p-threads ${task.cpus} \
      --i-maps ${params.q2cacheDir}:${mags_derep_index_file} \
      --i-mag-lengths ${params.q2cacheDir}:${mags_derep_lengths_file} \
      --o-abundances ${params.q2cacheDir}:mags_derep_ft \
    && touch mags_derep_ft
    """
}
