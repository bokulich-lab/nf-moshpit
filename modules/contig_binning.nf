process BIN_CONTIGS_METABAT {
    label "contigBinning"
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    errorStrategy { task.exitStatus == 125 ? 'ignore' : 'retry' }

    input:
    tuple val(sample_id), path(contigs_file), path(maps_file)

    output:
    tuple val(sample_id), path(key_mags), emit: bins
    tuple val(sample_id), path(key_contig_map), emit: contig_map
    tuple val(sample_id), path(key_unbinned_contigs), emit: unbinned_contigs

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    key_mags = "${params.runId}_mags_partitioned_${sample_id}"
    key_contig_map = "${params.runId}_contig_map_partitioned_${sample_id}"
    key_unbinned_contigs = "${params.runId}_unbinned_contigs_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}

    set +e
    qiime annotate bin-contigs-metabat \
      --verbose \
      --p-seed 42 \
      --p-num-threads ${task.cpus} \
      --i-contigs ${q2cacheDir}:${contigs_file} \
      --i-alignment-maps ${q2cacheDir}:${maps_file} \
      --o-mags "${q2cacheDir}:${key_mags}" \
      --o-contig-map "${q2cacheDir}:${key_contig_map}" \
      --o-unbinned-contigs "${q2cacheDir}:${key_unbinned_contigs}" > output.txt 2> error.txt

    qiime_exit_code=\$?
    echo "QIIME exit code: \$qiime_exit_code"
    set -e

    cat output.txt >> .command.out
    cat error.txt >> .command.err

    if grep -q "No MAGs were formed during binning" output.txt; then
      echo "No MAGs were formed during binning."
      exit 125
    fi

    touch ${key_mags}
    touch ${key_contig_map}
    touch ${key_unbinned_contigs}

    exit \$qiime_exit_code
    """
}

process EVALUATE_BINS_BUSCO {
    label "busco"
    storeDir params.storeDir
    scratch true
    tag "${_id}"
    errorStrategy 'retry'

    input:
    tuple val(lineage), val(_id), path(bins_file)
    path busco_db

    output:
    tuple val(_id), path(key), emit: busco_results

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
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
      --p-additional-metrics \
      ${lineage_dataset} \
      --i-mags ${q2cacheDir}:${bins_file} \
      --i-db ${params.databases.busco.cache}:${params.databases.busco.key} \
      --o-visualization "${params.runId}-mags-busco-${key}.qzv" \
      --o-results ${q2cacheDir}:${key} \
      ${params.binning.qc.busco.additionalFlags} \
    && touch ${key}
    """
}

process VISUALIZE_BUSCO {
    cpus 1
    memory { 2.GB * task.attempt }
    time { 1.h * task.attempt }
    publishDir params.publishDir, mode: 'copy'
    scratch true
    errorStrategy 'retry'

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
    time { 12.h * task.attempt }
    errorStrategy "retry"
    maxRetries 3
    storeDir params.storeDir
    scratch true
    clusterOptions = "--tmp=200G"

    output:
    path params.databases.busco.key

    script:
    """
    if [ -f ${params.databases.busco.cache}/keys/${params.databases.busco.key} ]; then
      echo 'Found an existing BUSCO database - fetching will be skipped.'
      touch ${params.databases.busco.key}
      exit 0
    fi
    qiime annotate fetch-busco-db \
      --verbose \
      --p-lineages ${params.databases.busco.fetchLineages.replaceAll(',', ' ')} \
      --o-db "${params.databases.busco.cache}:${params.databases.busco.key}" \
    && touch ${params.databases.busco.key}
    """
}

process FILTER_MAGS {
    cpus 1
    memory { 1.GB * task.attempt }
    time { 30.min * task.attempt }
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${_id}"
    errorStrategy 'retry'

    input:
    tuple val(_id), path(bins_file)
    path metadata_file
    val filtering_axis
    path q2_cache

    output:
    tuple val(_id), path(key_mags_filtered), emit: mags_filtered

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
    key_mags_filtered = "${params.runId}_mags_filtered_${_id}"
    """
    qiime annotate filter-mags \
      --verbose \
      --p-where "${params.binning.qc.filtering.condition}" \
      --p-exclude-ids ${params.binning.qc.filtering.exclude_ids} \
      --p-on ${filtering_axis} \
      --m-metadata-file ${params.q2cacheDir}:${metadata_file} \
      --i-mags ${q2cacheDir}:${bins_file} \
      --o-filtered-mags "${q2cacheDir}:${key_mags_filtered}" \
    && touch ${key_mags_filtered}
    """
}

process EVALUATE_BINS_CHECKM {
    label "checkm"
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'
    container params.containerCheckM

    input:
    path bins_file

    output:
    path "${params.runId}-mags-checkm.qzv"

    script:
    reducedTree = params.binning.qc.checkm.reducedTree ? "--p-reduced-tree" :  "--p-no-reduced-tree"
    """
    qiime checkm evaluate-bins \
      --verbose \
      --p-threads ${task.cpus} \
      --p-pplacer-threads ${task.cpus} \
      --p-db-path ${params.databases.checkm.path} \
      ${reducedTree} \
      ${params.binning.qc.checkm.additionalFlags} \
      --i-bins ${params.q2cacheDir}:${bins_file} \
      --o-visualization "${params.runId}-mags-checkm.qzv" \
    && touch "${params.runId}-mags-checkm.qzv"
    """
}
