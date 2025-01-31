process BIN_CONTIGS_METABAT {
    label "contigBinning"
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"

    input:
    tuple val(sample_id), path(contigs_file), path(maps_file)
    path q2_cache

    output:
    tuple val(sample_id), path(key_mags), emit: bins
    tuple val(sample_id), path(key_contig_map), emit: contig_map
    tuple val(sample_id), path(key_unbinned_contigs), emit: unbinned_contigs

    script:
    key_mags = "${params.runId}_mags_partitioned_${sample_id}"
    key_contig_map = "${params.runId}_contig_map_partitioned_${sample_id}"
    key_unbinned_contigs = "${params.runId}_unbinned_contigs_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime annotate bin-contigs-metabat \
      --verbose \
      --p-seed 42 \
      --p-num-threads ${task.cpus} \
      --i-contigs ${params.q2cacheDir}:${contigs_file} \
      --i-alignment-maps ${params.q2cacheDir}:${maps_file} \
      --o-mags "${params.q2cacheDir}:${key_mags}" \
      --o-contig-map "${params.q2cacheDir}:${key_contig_map}" \
      --o-unbinned-contigs "${params.q2cacheDir}:${key_unbinned_contigs}" \
    && touch ${key_mags} \
    && touch ${key_contig_map} \
    && touch ${key_unbinned_contigs}
    """
}

process EVALUATE_BINS_BUSCO {
    label "busco"
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"

    input:
    tuple val(lineage), val(_id), path(bins_file)
    path busco_db
    path q2_cache

    output:
    tuple val(_id), path(key), emit: busco_results

    script:
    if (params.binning.qc.busco.lineageDatasets == "auto") {
      lineage_dataset = "--p-auto-lineage"
      key = "${params.runId}_busco_results_partitioned_autolineage_${_id}"
    } else {
      lineage_dataset = "--p-lineage-dataset ${lineage}"
      key = "${params.runId}_busco_results_partitioned_${lineage}_${_id}"
    }
    """
    echo Processing sample ${_id}
    qiime annotate evaluate-busco \
      --verbose \
      --p-cpu ${task.cpus} \
      --p-mode ${params.binning.qc.busco.mode} \
      ${lineage_dataset} \
      --i-bins ${params.q2cacheDir}:${bins_file} \
      --i-busco-db ${params.binning.qc.busco.database.cache}:${params.binning.qc.busco.database.key} \
      --o-visualization "${params.runId}-mags-busco-${key}.qzv" \
      --o-results-table ${params.q2cacheDir}:${key} \
      ${params.binning.qc.busco.additionalFlags} \
    && touch ${key}
    """
}

process VISUALIZE_BUSCO {
    cpus 1
    memory 2.GB
    publishDir params.publishDir, mode: 'copy'
    scratch true

    input:
    path busco_results
    path q2_cache

    output:
    path "${params.runId}-mags-busco.qzv"

    script:
    """
    #!/usr/bin/env python

    from qiime2.plugins import annotate
    from qiime2 import Cache

    cache = Cache('${params.q2cacheDir}')
    results = cache.load('${busco_results}')

    print('Generating the final BUSCO visualization...')
    viz, = annotate.visualizers._visualize_busco(results)
    viz.save('${params.runId}-mags-busco.qzv')
    print('Visualization saved to "${params.runId}-mags-busco.qzv"')
    """
}

process FETCH_BUSCO_DB {
    label "needsInternet"
    cpus 1
    memory 4.GB
    time { 6.h * task.attempt }
    maxRetries 3
    storeDir "${params.binning.qc.busco.database.cache}/keys"
    scratch true

    input:
    path q2_cache

    output:
    path params.binning.qc.busco.database.key

    script:
    virus_flag = params.binning.qc.busco.database.types.contains("virus") ? "--p-virus True" : "--p-virus False"
    prok_flag = params.binning.qc.busco.database.types.contains("prok") ? "--p-prok True" : "--p-prok False"
    euk_flag = params.binning.qc.busco.database.types.contains("virus") ? "--p-euk True" : "--p-euk False"
    """
    if [ -f ${params.binning.qc.busco.database.cache}/keys/${params.binning.qc.busco.database.key} ]; then
      echo 'Found an existing BUSCO database - fetching will be skipped.'
      touch ${params.binning.qc.busco.database.key}
      exit 0
    fi
    qiime annotate fetch-busco-db \
      --verbose \
      ${virus_flag} \
      ${prok_flag} \
      ${euk_flag} \
      --o-busco-db "${params.binning.qc.busco.database.cache}:${params.binning.qc.busco.database.key}" \
    && touch ${params.binning.qc.busco.database.key}
    """
}

process FILTER_MAGS {
    cpus 1
    memory 1.GB
    time { 20.min * task.attempt }
    maxRetries 3
    storeDir params.storeDir
    scratch true

    input:
    path bins_file
    path metadata_file
    val filtering_axis
    path q2_cache

    output:
    path "${params.runId}_mags_filtered", emit: mags_filtered

    script:
    """
    qiime annotate filter-mags \
      --verbose \
      --p-where "${params.binning.qc.filtering.condition}" \
      --p-exclude-ids ${params.binning.qc.filtering.exclude_ids} \
      --p-on ${filtering_axis} \
      --m-metadata-file ${params.q2cacheDir}:${metadata_file} \
      --i-mags ${params.q2cacheDir}:${bins_file} \
      --o-filtered-mags "${params.q2cacheDir}:${params.runId}_mags_filtered" \
    && touch ${params.runId}_mags_filtered
    """
}
