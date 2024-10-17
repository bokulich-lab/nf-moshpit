process BIN_CONTIGS_METABAT {
    label "contigBinning"
    storeDir params.storeDir

    input:
    path contigs_file
    path maps_file
    path q2_cache

    output:
    path "mags", emit: bins
    path "contig_map", emit: contig_map
    path "unbinned_contigs", emit: unbinned_contigs

    """
    qiime moshpit bin-contigs-metabat \
      --verbose \
      --p-seed 42 \
      --p-num-threads ${task.cpus} \
      --i-contigs ${params.q2cacheDir}:${contigs_file} \
      --i-alignment-maps ${params.q2cacheDir}:${maps_file} \
      --o-mags "${params.q2cacheDir}:mags" \
      --o-contig-map "${params.q2cacheDir}:contig_map" \
      --o-unbinned-contigs "${params.q2cacheDir}:unbinned_contigs" \
    && touch mags \
    && touch contig_map \
    && touch unbinned_contigs
    """
}

process EVALUATE_BINS_CHECKM {
    label "checkm"
    conda params.condaEnvPathCheckM
    storeDir params.storeDir

    input:
    path bins_file
    path q2_cache

    output:
    path "mags-checkm.qzv"

    script:
    """
    qiime checkm evaluate-bins \
      --verbose \
      --p-threads ${task.cpus} \
      --p-pplacer-threads ${params.binning_qc.checkm.pplacerThreads} \
      --p-reduced-tree ${params.binning_qc.checkm.reducedTree} \
      --p-db-path ${params.binning_qc.checkm.DBpath} \
      --i-bins ${params.q2cacheDir}:${bins_file} \
      --o-visualization "mags-checkm.qzv"
    """
}

process EVALUATE_BINS_BUSCO {
    label "busco"
    storeDir params.storeDir

    input:
    path bins_file
    path busco_db
    path q2_cache

    output:
    path "mags-busco.qzv", emit: visualization
    path "busco_results", emit: busco_results

    script:
    if (params.binning_qc.busco.lineageDataset == "auto") {
      lineage_dataset = "--p-auto-lineage"
    } else {
      lineage_dataset = "--p-lineage-dataset ${params.binning_qc.busco.lineageDataset}"
    }
    """
    export TMPDIR=${params.tempDir}
    qiime moshpit evaluate-busco \
      --verbose \
      --p-cpu ${task.cpus} \
      --p-mode ${params.binning_qc.busco.mode} \
      ${lineage_dataset} \
      --i-bins ${params.q2cacheDir}:${bins_file} \
      --i-busco-db ${params.q2cacheDir}:${params.binning_qc.busco.database.key} \
      --o-visualization "mags-busco.qzv" \
      --o-results-table ${params.q2cacheDir}:busco_results \
      ${params.binning_qc.busco.additionalFlags} \
    && touch busco_results
    """
}

process FETCH_BUSCO_DB {
    label "needsInternet"
    cpus 1
    memory 1.GB
    time { 3.h * task.attempt }
    storeDir params.storeDir
    maxRetries 3

    input:
    path q2_cache

    output:
    path params.binning_qc.busco.database.key

    script:
    """
    if [ -f ${params.q2cacheDir}/keys/${params.binning_qc.busco.database.key} ]; then
      echo 'Found an existing BUSCO database - fetching will be skipped.'
      touch ${params.binning_qc.busco.database.key}
      exit 0
    fi
    qiime moshpit fetch-busco-db \
      --verbose \
      --p-virus ${params.binning_qc.busco.database.virus} \
      --p-prok ${params.binning_qc.busco.database.prok} \
      --p-euk ${params.binning_qc.busco.database.euk} \
      --o-busco-db "${params.q2cacheDir}:${params.binning_qc.busco.database.key}" \
    && touch ${params.binning_qc.busco.database.key}
    """
}
