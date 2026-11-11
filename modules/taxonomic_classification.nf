process CLASSIFY_KRAKEN2 {
    label "taxonomicClassificationKraken2"
    scratch true
    tag "${_id}"
    memory { (params.taxonomic_classification.kraken2.memory ?: 48).GB }
    errorStrategy "retry"
    maxRetries 3

    input:
    tuple val(_id), path(input_file)
    path kraken2_db
    val input_type

    output:
    tuple val(_id), path(reports_key), emit: reports
    tuple val(_id), path(hits_key), emit: hits
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
    if (input_type == "mags") {
      if (params.binning.qc.busco.enabled) {
        reports_key = "${params.runId}_kraken_reports_mags_${params.binning.primary}_partitioned_${params.binning.qc.busco.selectLineage}_${_id}"
        hits_key = "${params.runId}_kraken_outputs_mags_${params.binning.primary}_partitioned_${params.binning.qc.busco.selectLineage}_${_id}"
      } else {
        reports_key = "${params.runId}_kraken_reports_mags_${params.binning.primary}_partitioned_${_id}"
        hits_key = "${params.runId}_kraken_outputs_mags_${params.binning.primary}_partitioned_${_id}"
      }
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
      --i-seqs ${q2cacheDir}:${input_file} \
      --i-db ${params.databases.kraken2.cache}:${params.databases.kraken2.key} \
      --p-threads ${threads} \
      --p-memory-mapping ${params.taxonomic_classification.kraken2.memoryMapping} \
      --o-reports ${q2cacheDir}:${reports_key} \
      --o-outputs ${q2cacheDir}:${hits_key} \
      ${params.taxonomic_classification.kraken2.additionalFlags} \
    && touch ${reports_key} \
    && touch ${hits_key}
    """
}

process CLASSIFY_KRAKEN2_DEREP {
    label "taxonomicClassificationKraken2"
    scratch true
    tag "mags-derep"
    errorStrategy "retry"
    maxRetries 3
    memory { (params.taxonomic_classification.kraken2.memory ?: 48).GB }

    input:
    path input_file
    path kraken2_db
    path q2cacheDir

    output:
    path(reports_key), emit: reports
    path(hits_key), emit: hits
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    if (params.binning.qc.busco.enabled) {
      reports_key = "${params.runId}_kraken_reports_mags_${params.binning.primary}_derep_${params.binning.qc.busco.selectLineage}"
      hits_key = "${params.runId}_kraken_outputs_mags_${params.binning.primary}_derep_${params.binning.qc.busco.selectLineage}"
    } else {
      reports_key = "${params.runId}_kraken_reports_mags_${params.binning.primary}_derep"
      hits_key = "${params.runId}_kraken_outputs_mags_${params.binning.primary}_derep"
    }
    threads = 4 * task.cpus
    """
    echo Processing dereplicated MAGs
    qiime annotate classify-kraken2 \
      --verbose \
      --i-seqs ${params.q2cacheDir}:${input_file} \
      --i-db ${params.databases.kraken2.cache}:${params.databases.kraken2.key} \
      --p-threads ${threads} \
      --p-memory-mapping ${params.taxonomic_classification.kraken2.memoryMapping} \
      --o-reports ${params.q2cacheDir}:${reports_key} \
      --o-outputs ${params.q2cacheDir}:${hits_key} \
      ${params.taxonomic_classification.kraken2.additionalFlags} \
    && touch ${reports_key} \
    && touch ${hits_key}
    """
}

process ESTIMATE_BRACKEN {
    label "bracken"
    cpus 1
    time { 12.h * task.attempt }
    memory { 4.GB * task.attempt * (params.mem_multiplier as double)}
    errorStrategy "retry"
    maxRetries 3
    scratch true

    input:
    path kraken2_reports
    path bracken_db
    path q2_cache

    output:
    path "${params.runId}_bracken_reports_reads", emit: reports
    path "${params.runId}_bracken_taxonomy_reads", emit: taxonomy
    path "${params.runId}_bracken_feature_table_reads", emit: feature_table
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    """
    qiime annotate estimate-bracken \
      --verbose \
      --i-kraken2-reports ${params.q2cacheDir}:${kraken2_reports} \
      --i-db ${params.databases.bracken.cache}:${params.databases.bracken.key} \
      --p-threshold ${params.taxonomic_classification.bracken.threshold} \
      --p-read-len ${params.taxonomic_classification.bracken.readLength} \
      --p-level ${params.taxonomic_classification.bracken.level} \
      --o-reports ${params.q2cacheDir}:${params.runId}_bracken_reports_reads \
      --o-taxonomy "${params.q2cacheDir}:${params.runId}_bracken_taxonomy_reads" \
      --o-table "${params.q2cacheDir}:${params.runId}_bracken_feature_table_reads" \
    && touch ${params.runId}_bracken_reports_reads \
    && touch ${params.runId}_bracken_taxonomy_reads \
    && touch ${params.runId}_bracken_feature_table_reads
    """
}

process GET_KRAKEN_FEATURES {
    time { 4.h * task.attempt }
    memory { 2.GB * task.attempt }
    errorStrategy "retry"
    maxRetries 3
    scratch true

    input:
    path kraken2_reports
    path kraken2_hits
    val input_type

    output:
    path features, emit: taxonomy
    path ft_all, emit: feature_table, optional: true
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    features = "${params.runId}_kraken_features_${input_type}"
    ft_all = "${params.runId}_kraken_presence_absence_${input_type}"
    if (input_type == "mags") {
      features = "${params.runId}_kraken_features_mags_${params.binning.primary}"
      ft_all = "${params.runId}_kraken_presence_absence_mags_${params.binning.primary}"
    }
    if (input_type == "reads" || input_type == "mags") {
      """
      qiime annotate kraken2-to-features \
        --verbose \
        --i-reports ${params.q2cacheDir}:${kraken2_reports} \
        --p-coverage-threshold ${params.taxonomic_classification.feature_selection.coverageThreshold} \
        --o-taxonomy ${params.q2cacheDir}:${features} \
        --o-table "${params.q2cacheDir}:${ft_all}" \
      && touch ${features} \
      && touch ${ft_all}
      """
    } else {
      if (params.binning.qc.busco.enabled) {
        features = "${features}_${params.binning.qc.busco.selectLineage}"
      }
      """
      qiime annotate kraken2-to-mag-features \
        --verbose \
        --i-reports ${params.q2cacheDir}:${kraken2_reports} \
        --i-outputs ${params.q2cacheDir}:${kraken2_hits} \
        --p-coverage-threshold ${params.taxonomic_classification.feature_selection.coverageThreshold} \
        --o-taxonomy ${params.q2cacheDir}:${features} \
      && touch ${features}
      """
    }
}

process MAP_KRAKEN2_TAXONOMY_TO_CONTIGS {
    time { 4.h * task.attempt }
    memory { 2.GB * task.attempt * (params.mem_multiplier as double) }
    errorStrategy "retry"
    maxRetries 3
    // scratch true

    input:
    path kraken2_reports
    path kraken2_hits

    output:
    path taxonomy, emit: taxonomy
    path feature_map, emit: feature_map
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    taxonomy = "${params.runId}_kraken_taxonomy_contigs"
    feature_map = "${params.runId}_kraken_feature_map_contigs"

    """
    qiime annotate map-taxonomy-to-contigs \
      --verbose \
      --i-reports ${params.q2cacheDir}:${kraken2_reports} \
      --i-outputs ${params.q2cacheDir}:${kraken2_hits} \
      --p-coverage-threshold ${params.taxonomic_classification.feature_selection.coverageThreshold} \
      --o-taxonomy ${params.q2cacheDir}:${taxonomy} \
      --o-feature-map "${params.q2cacheDir}:${feature_map}" \
    && touch ${taxonomy} \
    && touch ${feature_map}
    """
}

process COLLAPSE_CONTIGS {
    time { 4.h * task.attempt }
    memory { 4.GB * task.attempt * (params.mem_multiplier as double) }
    errorStrategy "retry"
    maxRetries 3
    publishDir params.publishDir, mode: 'copy', pattern: '*.qzv'
    // scratch true

    input:
    path feature_map
    path taxonomy
    path contig_abundances

    output:
    path collapsed_table, emit: collapsed_table
    tuple val(viz_label), path("${params.runId}-contigs-collapsed.qzv"), emit: qzv
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    viz_label = "Collapsed contigs (Kraken2)"
    collapsed_table = "${params.runId}_contigs_collapsed_kraken2"
    """
    qiime annotate collapse-contigs \
      --verbose \
      --i-contig-map ${params.q2cacheDir}:${feature_map} \
      --i-taxonomy ${params.q2cacheDir}:${taxonomy} \
      --i-table ${params.q2cacheDir}:${contig_abundances} \
      --o-collapsed-table ${params.q2cacheDir}:${collapsed_table} \
      --o-visualization "${params.runId}-contigs-collapsed.qzv" \
    && touch ${collapsed_table}
    """
}

process CLASSIFY_KAIJU {
    label "taxonomicClassificationKaiju"
    scratch true
    tag "${_id}"
    memory { (params.taxonomic_classification.kaiju.memory ?: 48).GB }
    errorStrategy "retry"
    maxRetries 3

    input:
    tuple val(_id), path(input_file)
    path kaiju_db
    val input_type

    output:
    tuple val(_id), path(ft_key), emit: feature_table
    tuple val(_id), path(taxonomy_key), emit: taxonomy
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
    includeUnclassified = params.taxonomic_classification.kaiju.u ? "--p-u" :  "--p-no-u"
    // if (input_type == "mags") {
    //   if (params.binning.qc.busco.enabled) {
    //     reports_key = "${params.runId}_kraken_reports_mags_partitioned_${params.binning.qc.busco.selectLineage}_${_id}"
    //     hits_key = "${params.runId}_kraken_outputs_mags_partitioned_${params.binning.qc.busco.selectLineage}_${_id}"
    //   } else {
    //     reports_key = "${params.runId}_kraken_reports_mags_partitioned_${_id}"
    //     hits_key = "${params.runId}_kraken_outputs_mags_partitioned_${_id}"
    //   }
    // } else if (input_type == "mags-derep") {
    //   if (params.binning.qc.busco.enabled) {
    //     reports_key = "${params.runId}_kraken_reports_mags_derep_${params.binning.qc.busco.selectLineage}"
    //     hits_key = "${params.runId}_kraken_outputs_mags_derep_${params.binning.qc.busco.selectLineage}"
    //   } else {
    //     reports_key = "${params.runId}_kraken_reports_mags_derep"
    //     hits_key = "${params.runId}_kraken_outputs_mags_derep"
    //   }
    if (input_type == "reads") {
        ft_key = "${params.runId}_kaiju_ft_reads_partitioned_${_id}"
        taxonomy_key = "${params.runId}_kaiju_taxonomy_reads_partitioned_${_id}"
    } else if (input_type == "contigs") {
        ft_key = "${params.runId}_kaiju_ft_contigs_partitioned_${_id}"
        taxonomy_key = "${params.runId}_kaiju_taxonomy_contigs_partitioned_${_id}"
    }
    """
    echo Processing sample ${_id}
    qiime annotate classify-kaiju \
      --verbose \
      --i-seqs ${q2cacheDir}:${input_file} \
      --i-db ${params.databases.kaiju.cache}:${params.databases.kaiju.key} \
      --p-z ${task.cpus} \
      --p-a ${params.taxonomic_classification.kaiju.a} \
      --p-evalue ${params.taxonomic_classification.kaiju.evalue} \
      --p-m ${params.taxonomic_classification.kaiju.m} \
      --p-r ${params.taxonomic_classification.kaiju.r} \
      --p-c ${params.taxonomic_classification.kaiju.c} \
      ${includeUnclassified} \
      --o-abundances ${q2cacheDir}:${ft_key} \
      --o-taxonomy ${q2cacheDir}:${taxonomy_key} \
      ${params.taxonomic_classification.kaiju.additionalFlags} \
    && touch ${ft_key} \
    && touch ${taxonomy_key}
    """
}

process DRAW_TAXA_BARPLOT {
    time { 2.h * task.attempt }
    memory { 2.GB * task.attempt }
    errorStrategy "retry"
    publishDir params.publishDir, mode: 'copy'
    scratch true

    input:
    path feature_table
    path taxonomy
    val tool_name

    output:
    tuple val(viz_label), path("${params.runId}-${tool_name}-taxa-barplot.qzv"), emit: qzv
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    viz_label = "Taxa barplot: ${tool_name}"

    """
    qiime taxa barplot \
      --verbose \
      --i-table ${params.q2cacheDir}:${feature_table} \
      --i-taxonomy ${params.q2cacheDir}:${taxonomy} \
      --o-visualization "${params.runId}-${tool_name}-taxa-barplot.qzv"
    """
}

process FETCH_KRAKEN2_DB {
    label "needsInternet"
    cpus 1
    memory 2.GB
    time { 4.h * task.attempt }
    maxRetries 3
    scratch true

    output:
    path params.databases.kraken2.key, emit: kraken2_db
    path "bracken.ready", emit: bracken_db
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    needsBracken = params.taxonomic_classification.bracken.enabled && params.taxonomic_classification.enabledFor.contains('reads')
    brackenTarget = needsBracken ? "${params.databases.bracken.cache}:${params.databases.bracken.key}" : 'unused-bracken.qza'
    """
    kraken_exists=false
    bracken_exists=false
    if [ -f '${params.databases.kraken2.cache}/keys/${params.databases.kraken2.key}' ]; then kraken_exists=true; fi
    if [ '${needsBracken}' = 'true' ] && [ -f '${params.databases.bracken.cache}/keys/${params.databases.bracken.key}' ]; then bracken_exists=true; fi
    if \$kraken_exists && { [ '${needsBracken}' = 'false' ] || \$bracken_exists; }; then
        touch '${params.databases.kraken2.key}' bracken.ready
        exit 0
    fi
    if [ -z '${params.databases.kraken2.fetchCollection}' ]; then
        echo 'Missing Kraken2 or required Bracken artifact. Supply both cache entries or set databases.kraken2.fetchCollection to prepare missing databases.' >&2
        exit 1
    fi
    kraken_target='${params.databases.kraken2.cache}:${params.databases.kraken2.key}'
    if \$kraken_exists; then kraken_target='unused-kraken2.qza'; fi
    bracken_target='${brackenTarget}'
    if \$bracken_exists; then bracken_target='unused-bracken.qza'; fi
    qiime annotate build-kraken-db \
      --verbose \
      --p-collection '${params.databases.kraken2.fetchCollection}' \
      --o-kraken2-db "\$kraken_target" \
      --o-bracken-db "\$bracken_target"
    test -f '${params.databases.kraken2.cache}/keys/${params.databases.kraken2.key}'
    if [ '${needsBracken}' = 'true' ]; then test -f '${params.databases.bracken.cache}/keys/${params.databases.bracken.key}'; fi
    touch '${params.databases.kraken2.key}' bracken.ready
    """
}

process FETCH_KAIJU_DB {
    label "needsInternet"
    cpus 1
    memory 2.GB
    time { 4.h * task.attempt }
    maxRetries 3
    scratch true

    output:
    path params.databases.kaiju.key, emit: kaiju_db
    val true, emit: completion, topic: 'moshpit_analysis_done'

    script:
    """
    if [ -f ${params.databases.kaiju.cache}/keys/${params.databases.kaiju.key} ]; then
      echo 'Found an existing Kaiju database - fetching will be skipped.'
      touch ${params.databases.kaiju.key}
      exit 0
    fi
    qiime annotate fetch-kaiju-db \
      --verbose \
      --p-database-type ${params.databases.kaiju.databaseType} \
      --o-db "${params.databases.kaiju.cache}:${params.databases.kaiju.key}" \
    && touch ${params.databases.kaiju.key}
    """
}
