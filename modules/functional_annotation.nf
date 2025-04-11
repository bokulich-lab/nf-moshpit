process SEARCH_ORTHOLOGS_EGGNOG {
    label "orthologSearch"
    storeDir params.storeDir
    scratch true
    tag "${_id}"
    errorStrategy 'retry'

    input:
    tuple val(_id), path(input_file)
    val diamond_db
    val input_type

    output:
    tuple val(_id), path(hits_key), emit: hits
    tuple val(_id), path(table_key), emit: table

    script:
    if (input_type == "mags") {
        q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
        hits_key = "${params.runId}_eggnog_orthologs_mags_partitioned_${_id}"
        table_key = "${params.runId}_eggnog_table_mags_partitioned_${_id}"
    } else if (input_type == "contigs") {
        q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
        hits_key = "${params.runId}_eggnog_orthologs_contigs_partitioned_${_id}"
        table_key = "${params.runId}_eggnog_table_contigs_partitioned_${_id}"
    } else if (input_type == "mags_derep") {
        q2cacheDir = "${params.q2TemporaryCachesDir}/mags/${_id}"
        hits_key = "${params.runId}_eggnog_orthologs_mags_derep_partitioned_${_id}"
        table_key = "${params.runId}_eggnog_table_mags_derep_partitioned_${_id}"
    }
    """
    echo Processing sample ${_id}
    qiime annotate search-orthologs-diamond \
      --verbose \
      --p-num-cpus ${task.cpus} \
      --p-db-in-memory ${params.functional_annotation.ortholog_search.dbInMemory} \
      --i-sequences ${q2cacheDir}:${input_file} \
      --i-diamond-db ${params.functional_annotation.ortholog_search.database.cache}:${params.functional_annotation.ortholog_search.database.key} \
      --o-eggnog-hits ${q2cacheDir}:${hits_key} \
      --o-table ${q2cacheDir}:${table_key} \
      ${params.functional_annotation.ortholog_search.additionalFlags} \
    && touch ${table_key} \
    && touch ${hits_key}
    """
}

process ANNOTATE_EGGNOG {
    label "functionalAnnotation"
    storeDir params.storeDir
    scratch true
    tag "${_id}"
    errorStrategy 'retry'

    input:
    tuple val(_id), path(input_file)
    val eggnog_db
    val input_type

    output:
    tuple val(_id), path(annotations_key), emit: annotations

    script:
    if (input_type == "mags") {
        q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
        annotations_key = "${params.runId}_eggnog_annotations_mags_partitioned_${_id}"
    } else if (input_type == "contigs") {
        q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
        annotations_key = "${params.runId}_eggnog_annotations_contigs_partitioned_${_id}"
    } else if (input_type == "mags_derep") {
        q2cacheDir = "${params.q2TemporaryCachesDir}/mags/${_id}"
        annotations_key = "${params.runId}_eggnog_annotations_mags_derep_partitioned_${_id}"
    }
    """
    echo Processing sample ${_id}
    qiime annotate map-eggnog \
      --verbose \
      --p-db-in-memory ${params.functional_annotation.annotation.dbInMemory} \
      --p-num-cpus ${task.cpus} \
      --i-eggnog-hits ${q2cacheDir}:${input_file} \
      --i-eggnog-db ${params.functional_annotation.annotation.database.cache}:${params.functional_annotation.annotation.database.key} \
      --o-ortholog-annotations ${q2cacheDir}:${annotations_key} \
      ${params.functional_annotation.annotation.additionalFlags} \
    && touch ${annotations_key}
    """
}

process FETCH_DIAMOND_DB {
    label "needsInternet"
    time { 2.h * task.attempt }
    cpus 1
    maxRetries 3
    errorStrategy 'retry'
    storeDir params.storeDir
    scratch true

    output:
    path params.functional_annotation.ortholog_search.database.key

    script:
    """
    if [ -f ${params.functional_annotation.ortholog_search.database.cache}/keys/${params.functional_annotation.ortholog_search.database.key} ]; then
      echo 'Found an existing EggNOG Diamond database - fetching will be skipped.'
      touch ${params.functional_annotation.ortholog_search.database.key}
      exit 0
    fi
    qiime annotate fetch-diamond-db \
      --verbose \
      --o-diamond-db "${params.functional_annotation.ortholog_search.database.cache}:${params.functional_annotation.ortholog_search.database.key}" \
    && touch ${params.functional_annotation.ortholog_search.database.key}
    """
}

process FETCH_EGGNOG_DB {
    label "needsInternet"
    cpus 1
    memory 1.GB
    time { 2.h * task.attempt }
    maxRetries 3
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'

    output:
    path params.functional_annotation.annotation.database.key

    script:
    """
    if [ -f ${params.functional_annotation.annotation.database.cache}/keys/${params.functional_annotation.annotation.database.key} ]; then
      echo 'Found an existing EggNOG annotation database - fetching will be skipped.'
      touch ${params.functional_annotation.annotation.database.key}
      exit 0
    fi
    qiime annotate fetch-eggnog-db \
      --verbose \
      --o-eggnog-db "${params.functional_annotation.annotation.database.cache}:${params.functional_annotation.annotation.database.key}" \
    && touch ${params.functional_annotation.annotation.database.key}
    """
}

process EXTRACT_ANNOTATIONS {
    cpus 1
    memory 1.GB
    time { 15.min * task.attempt }
    maxRetries 3
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'

    input:
    path annotation_file
    val annotation_type
    val input_type
    path q2_cache

    output:
    tuple val(annotation_type), path("${params.runId}_${input_type}_${annotation_type}")

    script:
    """
    qiime annotate extract-annotations \
      --verbose \
      --p-annotation ${annotation_type} \
      --p-max-evalue ${params.functional_annotation.annotation.extract.max_evalue} \
      --p-min-score ${params.functional_annotation.annotation.extract.min_score} \
      --i-ortholog-annotations ${params.q2cacheDir}:${annotation_file} \
      --o-annotation-frequency "${params.q2cacheDir}:${params.runId}_${input_type}_${annotation_type}" \
    && touch ${params.runId}_${input_type}_${annotation_type}
    """
}

process MULTIPLY_TABLES {
    cpus 1
    memory 1.GB
    time { 15.min * task.attempt }
    maxRetries 3
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'

    input:
    path table1
    tuple val(annotation_type), path(table2)
    val input_type
    path q2_cache

    output:
    tuple val(annotation_type), path("${params.runId}_${input_type}_${annotation_type}_ft")

    script:
    """
    qiime annotate multiply-tables \
      --verbose \
      --i-table1 ${params.q2cacheDir}:${table1} \
      --i-table2 ${params.q2cacheDir}:${table2} \
      --o-result-table "${params.q2cacheDir}:${params.runId}_${input_type}_${annotation_type}_ft" \
    && touch ${params.runId}_${input_type}_${annotation_type}_ft
    """
}
