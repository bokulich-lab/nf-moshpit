process SEARCH_ORTHOLOGS_EGGNOG {
    conda params.condaEnvPath
    cpus params.functional_annotation.ortholog_search.cpus
    clusterOptions "--mem-per-cpu=${params.functional_annotation.ortholog_search.memoryPerCPU} ${params.functional_annotation.ortholog_search.clusterOptions}"
    storeDir params.storeDir
    time params.functional_annotation.ortholog_search.time

    input:
    path input_file
    val input_type

    output:
    path hits, emit: hits
    path table, emit: table

    script:
    if (input_type == "mags") {
        hits = "eggnog-orthologs-mags.qza"
        table = "eggnog-table-mags.qza"
    } else if (input_type == "contigs") {
        hits = "eggnog-orthologs-contigs.qza"
        table = "eggnog-table-contigs.qza"
    }
    """
    qiime moshpit eggnog-diamond-search \
      --verbose \
      --i-sequences ${input_file} \
      --i-diamond-db ${params.functional_annotation.ortholog_search.diamondDBpath} \
      --p-num-cpus ${task.cpus} \
      --p-db-in-memory ${params.functional_annotation.ortholog_search.dbInMemory} \
      --o-eggnog-hits ${hits} \
      --o-table ${table} \
      ${params.functional_annotation.ortholog_search.additionalFlags}
    """
}

process ANNOTATE_EGGNOG {
    conda params.condaEnvPath
    clusterOptions "--mem-per-cpu=${params.functional_annotation.annotation.memoryPerCPU} ${params.functional_annotation.annotation.clusterOptions}"
    storeDir params.storeDir
    time params.functional_annotation.annotation.time

    input:
    path input_file
    val input_type

    output:
    path annotations, emit: annotations

    script:
    if (input_type == "mags") {
        annotations = "eggnog-annotations-mags.qza"
    } else if (input_type == "contigs") {
        annotations = "eggnog-annotations-contigs.qza"
    }
    """
    qiime moshpit eggnog-annotate \
      --verbose \
      --i-eggnog-hits ${input_file} \
      --i-eggnog-db ${params.functional_annotation.annotation.eggnogDBpath} \
      --p-db-in-memory ${params.functional_annotation.annotation.dbInMemory} \
      --o-ortholog-annotations ${annotations} \
      ${params.functional_annotation.annotation.additionalFlags}
    """
}
