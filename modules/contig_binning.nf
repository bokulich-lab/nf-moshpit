process BIN_CONTIGS_METABAT {
    conda params.condaEnvPath
    cpus params.binning.cpus
    storeDir params.storeDir
    time params.binning.time
    clusterOptions "--mem-per-cpu=${params.binning.memoryPerCPU} ${params.binning.clusterOptions}"

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
    conda params.condaEnvPath
    cpus params.binning_qc.checkm.cpus
    storeDir params.storeDir
    time params.binning_qc.checkm.time
    clusterOptions "--mem-per-cpu=${params.binning_qc.checkm.memoryPerCPU} ${params.binning_qc.checkm.clusterOptions}"

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
    conda params.condaEnvPath
    cpus params.binning_qc.busco.cpus
    storeDir params.storeDir
    time params.binning_qc.busco.time
    clusterOptions "--mem-per-cpu=${params.binning_qc.busco.memoryPerCPU} ${params.binning_qc.busco.clusterOptions}"

    input:
    path bins_file
    path q2_cache

    output:
    path "mags-busco.qzv"

    script:
    if (params.binning_qc.busco.lineageDataset == "auto") {
      lineage_dataset = "--p-auto-lineage"
    } else {
      lineage_dataset = "--p-lineage-dataset ${params.binning_qc.busco.lineageDataset}"
    }
    """
    qiime moshpit evaluate-busco \
      --verbose \
      --p-cpu ${task.cpus} \
      --p-mode ${params.binning_qc.busco.mode} \
      ${lineage_dataset} \
      --i-bins ${params.q2cacheDir}:${bins_file} \
      --o-visualization "mags-busco.qzv" \
      ${params.binning_qc.busco.additionalFlags}
    """
}
