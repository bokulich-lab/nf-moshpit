process BIN_CONTIGS_METABAT {
    conda params.condaEnvPath
    cpus params.binning.cpus
    storeDir params.storeDir
    time params.binning.time

    input:
    path contigs_file
    path maps_file

    output:
    path "mags.qza", emit: bins
    path "contig-map.qza", emit: contig_map

    """
    qiime moshpit bin-contigs-metabat \
      --verbose \
      --p-seed 42 \
      --p-num-threads ${task.cpus} \
      --i-contigs ${contigs_file} \
      --i-alignment-maps ${maps_file} \
      --o-mags "mags.qza" \
      --o-contig-map "contig-map.qza"
    """
}

process EVALUATE_BINS {
    conda params.condaEnvPath
    cpus params.binning_qc.cpus
    clusterOptions params.binning_qc.clusterOptions
    storeDir params.storeDir
    time params.binning_qc.time

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
