process BIN_CONTIGS_METABAT {
    label "contigBinningMetabat2"
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    errorStrategy { task.exitStatus == 125 ? 'ignore' : 'retry' }
    clusterOptions params.binning.metabat2.clusterOptions

    input:
    tuple val(sample_id), path(contigs_file), path(maps_file)

    output:
    tuple val(sample_id), path(key_mags), emit: bins
    tuple val(sample_id), path(key_contig_map), emit: contig_map
    tuple val(sample_id), path(key_unbinned_contigs), emit: unbinned_contigs

    script:
    def binner = 'metabat2'
    def metabat = params.binning.metabat2
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    key_mags = "${params.runId}_mags_${binner}_partitioned_${sample_id}"
    key_contig_map = "${params.runId}_contig_map_${binner}_partitioned_${sample_id}"
    key_unbinned_contigs = "${params.runId}_unbinned_contigs_${binner}_partitioned_${sample_id}"
    min_contig_flag = metabat.min_contig != null ? "--p-min-contig ${metabat.min_contig}" : ""
    """
    echo Processing sample ${sample_id} with MetaBAT2

    set +e
    qiime mag bin-contigs-metabat \
      --verbose \
      --p-seed ${metabat.seed} \
      --p-num-threads ${task.cpus} \
      ${min_contig_flag} \
      ${metabat.additionalFlags} \
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

    touch ${key_mags}
    touch ${key_contig_map}
    touch ${key_unbinned_contigs}

    if grep -q "No MAGs were formed during binning" output.txt || grep -q "No MAGs were formed during binning" error.txt; then
      echo "No MAGs were formed during binning."
      exit 125
    fi

    if grep -q "There were no large target contigs" output.txt || grep -q "There were no large target contigs" error.txt; then
      echo "There were no large target contigs."
      exit 125
    fi

    exit \$qiime_exit_code
    """
}

process BIN_CONTIGS_SEMIBIN2 {
    label "contigBinningSemibin2"
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    errorStrategy { task.exitStatus == 125 ? 'ignore' : 'retry' }
    clusterOptions params.binning.semibin2.clusterOptions

    input:
    tuple val(sample_id), path(contigs_file), path(maps_file)

    output:
    tuple val(sample_id), path(key_mags), emit: bins
    tuple val(sample_id), path(key_contig_map), emit: contig_map

    script:
    def binner = 'semibin2'
    def semibin = params.binning.semibin2
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    key_mags = "${params.runId}_mags_${binner}_partitioned_${sample_id}"
    key_contig_map = "${params.runId}_contig_map_${binner}_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id} with SemiBin2

    set +e
    qiime mag bin-contigs-semibin2 \
      --verbose \
      --p-threads ${task.cpus} \
      --p-training-type ${semibin.training_type} \
      --p-environment ${semibin.environment} \
      --p-min-len ${semibin.min_len} \
      --p-epochs ${semibin.epochs} \
      --p-batch-size ${semibin.batch_size} \
      --p-random-seed ${semibin.random_seed} \
      ${semibin.additionalFlags} \
      --i-contigs ${q2cacheDir}:${contigs_file} \
      --i-alignment-maps ${q2cacheDir}:${maps_file} \
      --o-mags "${q2cacheDir}:${key_mags}" \
      --o-contig-map "${q2cacheDir}:${key_contig_map}" > output.txt 2> error.txt

    qiime_exit_code=\$?
    echo "QIIME exit code: \$qiime_exit_code"
    set -e

    cat output.txt >> .command.out
    cat error.txt >> .command.err

    touch ${key_mags}
    touch ${key_contig_map}

    if grep -q "No MAGs were formed during binning" output.txt || grep -q "No MAGs were formed during binning" error.txt; then
      echo "No MAGs were formed during binning."
      exit 125
    fi

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
    val binner
    tuple val(lineage), val(_id), path(bins_file), path(unbinned_contigs)
    path busco_db

    output:
    tuple val(lineage), val(_id), path(key), emit: busco_results

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
    if (params.binning.qc.busco.lineageDatasets == "auto") {
      lineage_dataset = "--p-auto-lineage"
      key = "${params.runId}_busco_results_${binner}_partitioned_autolineage_${_id}"
    } else {
      lineage_dataset = "--p-lineage-dataset ${lineage}"
      key = "${params.runId}_busco_results_${binner}_partitioned_${lineage}_${_id}"
    }
    """
    echo "Processing sample ${_id} (binner: ${binner})"
    qiime mag evaluate-busco \
      --verbose \
      --p-cpu ${task.cpus} \
      --p-mode ${params.binning.qc.busco.mode} \
      --p-additional-metrics \
      ${lineage_dataset} \
      --i-mags ${q2cacheDir}:${bins_file} \
      --i-db ${params.databases.busco.cache}:${params.databases.busco.key} \
      --i-unbinned-contigs ${q2cacheDir}:${unbinned_contigs} \
      --o-visualization "${params.runId}-mags-busco-${binner}-${key}.qzv" \
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
    tag "${lineage}"

    input:
    val binner
    tuple val(lineage), path(busco_results)
    path q2_cache

    output:
    tuple val(viz_label), path("${params.runId}-mags-busco-${binner}-${lineage}.qzv"), emit: qzv

    script:
    viz_label = "Bins QC (BUSCO, ${binner}): ${lineage}"
    """
    #!/usr/bin/env python

    from qiime2.plugins import mag
    from qiime2 import Cache

    cache = Cache('${params.q2cacheDir}')
    results = cache.load('${busco_results}')

    print('Generating the final BUSCO visualization...')
    viz, = mag.visualizers._visualize_busco(results)
    viz.save('${params.runId}-mags-busco-${binner}-${lineage}.qzv')
    print('Visualization saved to "${params.runId}-mags-busco-${binner}-${lineage}.qzv"')
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
    qiime mag fetch-busco-db \
      --verbose \
      --p-lineages ${params.databases.busco.fetchLineages.replaceAll(',', ' ')} \
      --o-db "${params.databases.busco.cache}:${params.databases.busco.key}" \
    && touch ${params.databases.busco.key}
    """
}

process FILTER_MAGS {
    cpus 1
    memory { 2.GB * task.attempt }
    time { 1.h * task.attempt }
    maxRetries 3
    storeDir params.storeDir
    tag "${_id}"
    errorStrategy { task.exitStatus == 125 ? 'ignore' : 'retry' }

    input:
    val binner
    tuple val(_id), path(bins_file), val(lineage)
    path metadata_file
    val filtering_axis
    path q2_cache

    output:
    tuple val(_id), path(key_mags_filtered), val(lineage), emit: mags_filtered

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
    key_mags_filtered = "${params.runId}_mags_${binner}_filtered_${lineage}_${_id}"
    """
    echo Processing: ${_id}
    set +e

    qiime mag filter-mags \
      --verbose \
      --p-where "${params.binning.qc.filtering.condition}" \
      --p-exclude-ids ${params.binning.qc.filtering.exclude_ids} \
      --p-on ${filtering_axis} \
      --m-metadata-file ${params.q2cacheDir}:${metadata_file} \
      --i-mags ${q2cacheDir}:${bins_file} \
      --o-filtered-mags "${q2cacheDir}:${key_mags_filtered}" > output.txt 2> error.txt

    qiime_exit_code=\$?
    echo "QIIME exit code: \$qiime_exit_code"
    set -e

    cat output.txt >> .command.out
    cat error.txt >> .command.err

    touch ${key_mags_filtered}
    
    if grep -q "No MAGs remain after filtering" output.txt || grep -q "No MAGs remain after filtering" error.txt; then
      echo "No MAGs remain after filtering."
      exit 125
    fi
    
    exit \$qiime_exit_code
    """
}

process EVALUATE_BINS_CHECKM {
    label "checkm"
    storeDir params.storeDir
    scratch true
    errorStrategy 'retry'

    input:
    val binner
    path bins_file

    output:
    tuple val(viz_label), path("${params.runId}-mags-checkm-${binner}.qzv"), emit: qzv

    script:
    viz_label = "Bins QC (CheckM, ${binner})"
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
      --o-visualization "${params.runId}-mags-checkm-${binner}.qzv"
    """
}

process COLLATE_BUSCO_RESULTS {
    label "collationBusco"
    storeDir params.storeDir
    cpus 1
    time { 2.h * task.attempt }
    memory { 4.GB * task.attempt }
    errorStrategy 'retry'
    maxRetries 3
    tag "${lineage}"

    input:
    val lineage
    val ids_and_paths
    val cache_key_out 
    val qiime_action
    val qiime_input_flag
    val qiime_output_flag
    val clean_up

    output:
    tuple val(lineage), path("${cache_key_out}_${lineage}"), emit: collated_results

    script:
    def sample_ids = ids_and_paths[0]
    def sample_paths = ids_and_paths[1]
    
    def inputString = [sample_ids, sample_paths].transpose().collect { sample_id, path ->
        def key = new File(path.toString()).getName()
        "${params.q2TemporaryCachesDir}/${sample_id}:${key}"
    }.join(' ')
  
    """
    echo "Combined input: ${inputString}"
    echo "Sample IDs: ${sample_ids}"
    echo "Lineage: ${lineage}"
    
    qiime ${qiime_action} \
      ${qiime_input_flag} ${inputString} \
      ${qiime_output_flag} ${params.q2cacheDir}:${cache_key_out}_${lineage} \
    && touch ${cache_key_out}_${lineage}

    if [ ${params.binning.qc.busco.cleanUp} == true ]; then
      echo "Cleaning up BUSCO results..."
      for cache_entry in ${inputString}; do
        cache_dir=\$(echo \$cache_entry | cut -d: -f1)
        cache_key=\$(echo \$cache_entry | cut -d: -f2)
        echo "Removing cache key: \$cache_dir:\$cache_key"
        qiime tools cache-remove --cache \$cache_dir --key \$cache_key
      done
    fi
    """
}
