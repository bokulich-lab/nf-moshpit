process SEARCH_ORTHOLOGS_EGGNOG {
    label "functionalAnnotation"
    cpus 1
    memory 1.GB
    time params.functionalAnnotation.time
    storeDir params.storeDir

    input:
    path input_file
    val diamond_db
    val input_type
    path q2_cache

    output:
    path hits, emit: hits
    path table, emit: table

    script:
    if (input_type == "mags") {
        hits = "eggnog_orthologs_mags"
        table = "eggnog_table_mags"
    } else if (input_type == "contigs") {
        hits = "eggnog_orthologs_contigs"
        table = "eggnog_table_contigs"
    } else if (input_type == "mags_derep") {
        hits = "eggnog_orthologs_mags_derep"
        table = "eggnog_table_mags_derep"
    }
    """
    python ${projectDir}/../scripts/generate_toml.py \
      -t ${projectDir}/../conf/parallel.template.toml \
      -o parallel.toml \
      -m '${params.functionalAnnotation.memory}' \
      -c ${params.functionalAnnotation.cpus} \
      -T ${params.functionalAnnotation.time} \
      -n 1 \
      -b ${params.functionalAnnotation.blocks} \
      -w "${params.functionalAnnotation.workerInit}"

    cat parallel.toml

    qiime moshpit eggnog-diamond-search \
      --verbose \
      --p-num-cpus ${task.cpus} \
      --p-db-in-memory ${params.functional_annotation.ortholog_search.dbInMemory} \
      --i-sequences ${params.q2cacheDir}:${input_file} \
      --i-diamond-db ${params.functional_annotation.ortholog_search.database.cache}:${params.functional_annotation.ortholog_search.database.key} \
      --o-eggnog-hits ${params.q2cacheDir}:${hits} \
      --o-table ${params.q2cacheDir}:${table} \
      --no-recycle \
      --parallel-config parallel.toml \
      --use-cache ${params.q2cacheDir} \
      ${params.functional_annotation.ortholog_search.additionalFlags} \
    && touch ${table} \
    && touch ${hits}
    """
}

process ANNOTATE_EGGNOG {
    label "functionalAnnotation"
    cpus 1
    memory 1.GB
    time params.functionalAnnotation.time
    storeDir params.storeDir

    input:
    path input_file
    val eggnog_db
    val input_type
    path q2_cache

    output:
    path annotations, emit: annotations

    script:
    if (input_type == "mags") {
        annotations = "eggnog_annotations_mags"
    } else if (input_type == "contigs") {
        annotations = "eggnog_annotations_contigs"
    } else if (input_type == "mags_derep") {
        annotations = "eggnog_annotations_mags_derep"
    }
    """
    python ${projectDir}/../scripts/generate_toml.py \
      -t ${projectDir}/../conf/parallel.template.toml \
      -o parallel.toml \
      -m '${params.functionalAnnotation.memory}' \
      -c ${params.functionalAnnotation.cpus} \
      -T ${params.functionalAnnotation.time} \
      -n 1 \
      -b ${params.functionalAnnotation.blocks} \
      -w "${params.functionalAnnotation.workerInit}"

    cat parallel.toml

    qiime moshpit eggnog-annotate \
      --verbose \
      --p-db-in-memory ${params.functional_annotation.annotation.dbInMemory} \
      --p-num-cpus ${task.cpus} \
      --i-eggnog-hits ${params.q2cacheDir}:${input_file} \
      --i-eggnog-db ${params.functional_annotation.annotation.database.cache}:${params.functional_annotation.annotation.database.key} \
      --o-ortholog-annotations ${params.q2cacheDir}:${annotations} \
      --no-recycle \
      --parallel-config parallel.toml \
      --use-cache ${params.q2cacheDir} \
      ${params.functional_annotation.annotation.additionalFlags} \
    && touch ${annotations}
    """
}

process FETCH_DIAMOND_DB {
    label "needsInternet"
    time { 2.h * task.attempt }
    cpus 1
    storeDir params.storeDir
    maxRetries 3

    input:
    path q2_cache

    output:
    path params.functional_annotation.ortholog_search.database.key

    script:
    """
    if [ -f ${params.functional_annotation.ortholog_search.database.cache}/keys/${params.functional_annotation.ortholog_search.database.key} ]; then
      echo 'Found an existing EggNOG Diamond database - fetching will be skipped.'
      touch ${params.functional_annotation.ortholog_search.database.key}
      exit 0
    fi
    qiime moshpit fetch-diamond-db \
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
    storeDir params.storeDir
    maxRetries 3

    input:
    path q2_cache

    output:
    path params.functional_annotation.annotation.database.key

    script:
    """
    if [ -f ${params.functional_annotation.annotation.database.cache}/keys/${params.functional_annotation.annotation.database.key} ]; then
      echo 'Found an existing EggNOG annotation database - fetching will be skipped.'
      touch ${params.functional_annotation.annotation.database.key}
      exit 0
    fi
    qiime moshpit fetch-eggnog-db \
      --verbose \
      --o-eggnog-db "${params.functional_annotation.annotation.database.cache}:${params.functional_annotation.annotation.database.key}" \
    && touch ${params.functional_annotation.annotation.database.key}
    """
}

process EXTRACT_ANNOTATIONS {
    storeDir params.storeDir
    cpus 1
    memory 1.GB
    time { 15.min * task.attempt }
    maxRetries 3

    input:
    path annotation_file
    val annotation_type
    val input_type
    path q2_cache

    output:
    path "${input_type}_${annotation_type}"

    script:
    """
    qiime moshpit extract-annotations \
      --verbose \
      --p-annotation ${annotation_type} \
      --p-max-evalue ${params.functional_annotation.annotation.extract.max_evalue} \
      --p-min-score ${params.functional_annotation.annotation.extract.min_score} \
      --i-ortholog-annotations ${params.q2cacheDir}:${annotation_file} \
      --o-annotation-frequency "${params.q2cacheDir}:${input_type}_${annotation_type}" \
    && touch ${input_type}_${annotation_type}
    """
}

process MULTIPLY_TABLES {
    storeDir params.storeDir
    cpus 1
    memory 1.GB
    time { 15.min * task.attempt }
    maxRetries 3

    input:
    path table1
    path table2
    val annotation_type
    path q2_cache

    output:
    path "${annotation_type}_ft"

    script:
    """
    qiime moshpit multiply-tables \
      --verbose \
      --i-table1 ${params.q2cacheDir}:${table1} \
      --i-table2 ${params.q2cacheDir}:${table2} \
      --o-result-table "${params.q2cacheDir}:${annotation_type}_ft" \
    && touch ${annotation_type}_ft
    """
}
