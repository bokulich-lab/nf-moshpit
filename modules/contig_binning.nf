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
    path "mags.qza", emit: bins
    path "contig-map.qza", emit: contig_map
    path "unbinned-contigs.qza", emit: unbinned_contigs

    """
    qiime moshpit bin-contigs-metabat \
      --verbose \
      --p-seed 42 \
      --p-num-threads ${task.cpus} \
      --i-contigs ${params.q2cacheDir}:${contigs_file} \
      --i-alignment-maps ${params.q2cacheDir}:${maps_file} \
      --o-mags "mags.qza" \
      --o-contig-map "contig-map.qza" \
      --o-unbinned-contigs "unbinned-contigs.qza"
    """
}

process EVALUATE_BINS {
    conda params.condaEnvPath
    cpus params.binning_qc.cpus
    storeDir params.storeDir
    time params.binning_qc.time
    clusterOptions "--mem-per-cpu=${params.binning_qc.memoryPerCPU} ${params.binning_qc.clusterOptions}"

    input:
    path bins_file

    output:
    path "mags.qzv"

    script:
    """
    qiime checkm evaluate-bins \
      --verbose \
      --p-threads ${task.cpus} \
      --p-pplacer-threads ${params.binning_qc.pplacerThreads} \
      --p-reduced-tree ${params.binning_qc.checkmReducedTree} \
      --p-db-path ${params.binning_qc.checkmDBpath} \
      --i-bins ${bins_file} \
      --o-visualization "mags.qzv"
    """
}
