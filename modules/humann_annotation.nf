process FETCH_CHOCOPHLAN_DB {
    label "needsInternet"
    cpus 1
    memory 2.GB
    time { 4.h * task.attempt }
    maxRetries 3
    errorStrategy 'retry'
    storeDir params.storeDir
    scratch true

    output:
    path params.databases.humann3Chocophlan.key, emit: chocophlan_db

    script:
    """
    if [ -f ${params.databases.humann3Chocophlan.cache}/keys/${params.databases.humann3Chocophlan.key} ]; then
      echo 'Found an existing ChocoPhlAn database - fetching will be skipped.'
      touch ${params.databases.humann3Chocophlan.key}
      exit 0
    fi
    qiime humann3 download-chocophlan-database \
      --verbose \
      --o-database "${params.databases.humann3Chocophlan.cache}:${params.databases.humann3Chocophlan.key}" \
    && touch ${params.databases.humann3Chocophlan.key}
    """
}

process FETCH_TRANSLATED_SEARCH_DB {
    label "needsInternet"
    cpus 1
    memory 2.GB
    time { 4.h * task.attempt }
    maxRetries 3
    errorStrategy 'retry'
    storeDir params.storeDir
    scratch true

    output:
    path params.databases.humann3TranslatedSearch.key, emit: translated_search_db

    script:
    """
    if [ -f ${params.databases.humann3TranslatedSearch.cache}/keys/${params.databases.humann3TranslatedSearch.key} ]; then
      echo 'Found an existing translated-search database - fetching will be skipped.'
      touch ${params.databases.humann3TranslatedSearch.key}
      exit 0
    fi
    qiime humann3 download-translated-search-database \
      --verbose \
      --p-build ${params.databases.humann3TranslatedSearch.build} \
      --o-database "${params.databases.humann3TranslatedSearch.cache}:${params.databases.humann3TranslatedSearch.key}" \
    && touch ${params.databases.humann3TranslatedSearch.key}
    """
}

process FETCH_METAPHLAN_DB {
    label "needsInternet"
    cpus params.databases.humann3Metaphlan.cpus
    memory 4.GB
    time { 4.h * task.attempt }
    maxRetries 3
    errorStrategy 'retry'
    storeDir params.storeDir
    scratch true

    output:
    path params.databases.humann3Metaphlan.key, emit: metaphlan_db

    script:
    """
    if [ -f ${params.databases.humann3Metaphlan.cache}/keys/${params.databases.humann3Metaphlan.key} ]; then
      echo 'Found an existing MetaPhlAn database - fetching will be skipped.'
      touch ${params.databases.humann3Metaphlan.key}
      exit 0
    fi
    qiime humann3 download-metaphlan-database \
      --verbose \
      --p-index ${params.databases.humann3Metaphlan.index} \
      --p-cpus ${params.databases.humann3Metaphlan.cpus} \
      --o-database "${params.databases.humann3Metaphlan.cache}:${params.databases.humann3Metaphlan.key}" \
    && touch ${params.databases.humann3Metaphlan.key}
    """
}

process PROFILE_READS_HUMANN {
    label "humann3Profiling"
    storeDir params.storeDir
    scratch true
    tag "${_id}"
    errorStrategy 'retry'
    maxRetries 2
    clusterOptions params.humann3.clusterOptions

    input:
    tuple val(_id), path(input_file)
    path chocophlan_db
    path translated_search_db
    path metaphlan_db

    output:
    tuple val(_id), path(gene_families_key), emit: gene_families
    tuple val(_id), path(path_abundance_key), emit: path_abundance
    tuple val(_id), path(metaphlan_profile_key), emit: metaphlan_profile
    tuple val(_id), path(reactions_key), emit: reactions

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
    gene_families_key = "${params.runId}_humann_gene_families_reads_partitioned_${_id}"
    path_abundance_key = "${params.runId}_humann_path_abundance_reads_partitioned_${_id}"
    metaphlan_profile_key = "${params.runId}_humann_metaphlan_profiles_reads_partitioned_${_id}"
    reactions_key = "${params.runId}_humann_reactions_reads_partitioned_${_id}"
    translated_identity_flag = ''
    if (params.humann3.translated_identity_threshold != null
        && params.humann3.translated_identity_threshold.toString().trim() != ''
        && params.humann3.translated_identity_threshold.toString().toLowerCase() != 'null') {
        translated_identity_flag = "--p-translated-identity-threshold ${params.humann3.translated_identity_threshold}"
    }
    """
    echo Processing sample ${_id}
    qiime humann3 _run-humann \
      --verbose \
      --i-reads ${q2cacheDir}:${input_file} \
      --i-nucleotide-database ${params.databases.humann3Chocophlan.cache}:${params.databases.humann3Chocophlan.key} \
      --i-translated-search-database ${params.databases.humann3TranslatedSearch.cache}:${params.databases.humann3TranslatedSearch.key} \
      --i-metaphlan-database ${params.databases.humann3Metaphlan.cache}:${params.databases.humann3Metaphlan.key} \
      --p-threads ${task.cpus} \
      --p-memory-use ${params.humann3.memory_use} \
      --p-prescreen-threshold ${params.humann3.prescreen_threshold} \
      --p-nucleotide-identity-threshold ${params.humann3.nucleotide_identity_threshold} \
      --p-nucleotide-query-coverage-threshold ${params.humann3.nucleotide_query_coverage_threshold} \
      --p-nucleotide-subject-coverage-threshold ${params.humann3.nucleotide_subject_coverage_threshold} \
      ${translated_identity_flag} \
      --p-translated-query-coverage-threshold ${params.humann3.translated_query_coverage_threshold} \
      --p-translated-subject-coverage-threshold ${params.humann3.translated_subject_coverage_threshold} \
      --p-evalue ${params.humann3.evalue} \
      --p-gap-fill ${params.humann3.gap_fill} \
      --p-minpath ${params.humann3.minpath} \
      --p-pathways ${params.humann3.pathways} \
      --p-output-max-decimals ${params.humann3.output_max_decimals} \
      --p-log-level ${params.humann3.log_level} \
      --o-gene-families ${q2cacheDir}:${gene_families_key} \
      --o-path-abundance ${q2cacheDir}:${path_abundance_key} \
      --o-metaphlan-profile ${q2cacheDir}:${metaphlan_profile_key} \
      --o-reactions ${q2cacheDir}:${reactions_key} \
      ${params.humann3.additionalFlags} \
    && touch ${gene_families_key} \
    && touch ${path_abundance_key} \
    && touch ${metaphlan_profile_key} \
    && touch ${reactions_key}
    """
}

process COLLATE_HUMANN_PARTITIONS {
    label "collation"
    cpus 1
    time { 2.h * task.attempt }
    memory { 2.GB * task.attempt }
    errorStrategy 'retry'
    storeDir params.storeDir
    maxRetries 3

    input:
    val id_and_paths
    val cache_key_out
    val qiime_action
    val qiime_input_flag
    val qiime_output_flag
    val clean_up

    output:
    path "${cache_key_out}"

    script:
    def inputString = id_and_paths.collect { item ->
        def sample_id = item[0]
        def path = item[1]
        def key = new File(path.toString()).getName()
        "${params.q2TemporaryCachesDir}/${sample_id}:${key}"
    }.join(' ')

    """
    echo "Combined input: ${inputString}"

    qiime ${qiime_action} \
      ${qiime_input_flag} ${inputString} \
      ${qiime_output_flag} ${params.q2cacheDir}:${cache_key_out} \
    && touch ${cache_key_out}
    """
}

process CONVERT_HUMANN_GENE_FAMILIES {
    label "humann3Conversion"
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'
    maxRetries 3

    input:
    path gene_families_table
    path q2_cache

    output:
    path feature_table_key, emit: feature_table
    path taxonomy_key, emit: taxonomy

    script:
    feature_table_key = "${params.runId}_humann_gene_families_reads_ft"
    taxonomy_key = "${params.runId}_humann_gene_families_reads_taxonomy"
    destratify_flag = params.humann3.conversion.destratify ? "--p-destratify" : ""
    """
    qiime sapienns humann-genefamily \
      --verbose \
      --i-genefamily-table ${params.q2cacheDir}:${gene_families_table} \
      --o-table ${params.q2cacheDir}:${feature_table_key} \
      --o-taxonomy ${params.q2cacheDir}:${taxonomy_key} \
      ${destratify_flag} \
      ${params.humann3.conversion.additionalFlags} \
    && touch ${feature_table_key} \
    && touch ${taxonomy_key}
    """
}

process CONVERT_HUMANN_PATH_ABUNDANCE {
    label "humann3Conversion"
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'
    maxRetries 3

    input:
    path path_abundance_table
    path q2_cache

    output:
    path feature_table_key, emit: feature_table
    path taxonomy_key, emit: taxonomy

    script:
    feature_table_key = "${params.runId}_humann_path_abundance_reads_ft"
    taxonomy_key = "${params.runId}_humann_path_abundance_reads_taxonomy"
    destratify_flag = params.humann3.conversion.destratify ? "--p-destratify" : ""
    """
    qiime sapienns humann-pathway \
      --verbose \
      --i-pathway-table ${params.q2cacheDir}:${path_abundance_table} \
      --o-table ${params.q2cacheDir}:${feature_table_key} \
      --o-taxonomy ${params.q2cacheDir}:${taxonomy_key} \
      ${destratify_flag} \
      ${params.humann3.conversion.additionalFlags} \
    && touch ${feature_table_key} \
    && touch ${taxonomy_key}
    """
}

process CONVERT_METAPHLAN_PROFILE {
    label "humann3Conversion"
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'
    maxRetries 3

    input:
    path metaphlan_profile_table
    path q2_cache

    output:
    path feature_table_key, emit: feature_table
    path taxonomy_key, emit: taxonomy

    script:
    feature_table_key = "${params.runId}_humann_metaphlan_profiles_reads_ft"
    taxonomy_key = "${params.runId}_humann_metaphlan_profiles_reads_taxonomy"
    """
    qiime sapienns metaphlan-taxon \
      --verbose \
      --i-stratified-table ${params.q2cacheDir}:${metaphlan_profile_table} \
      --p-level ${params.humann3.conversion.metaphlan_level} \
      --o-table ${params.q2cacheDir}:${feature_table_key} \
      --o-taxonomy ${params.q2cacheDir}:${taxonomy_key} \
      ${params.humann3.conversion.additionalFlags} \
    && touch ${feature_table_key} \
    && touch ${taxonomy_key}
    """
}

process FETCH_HUMANN_ARTIFACT {
    publishDir params.publishDir, mode: 'copy'
    memory { 4.GB * task.attempt }
    time { 2.h * task.attempt }
    maxRetries 3
    errorStrategy 'retry'

    input:
    val cache_key

    output:
    path artifact_name

    script:
    cache_key = new File(cache_key.toString()).getName()
    artifact_name = cache_key.replace("_", "-") + ".qza"
    """
    qiime tools cache-fetch \
      --cache ${params.q2cacheDir} \
      --key ${cache_key} \
      --output-path ${artifact_name}
    """
}
