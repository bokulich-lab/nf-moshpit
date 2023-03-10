process BIN_CONTIGS_METABAT {
    conda params.condaEnvPath
    cpus params.binning.cpus
    storeDir params.storeDir
    time params.binning.time

    input:
    path contigs_file
    path maps_file

    output:
    path "paired-end-mags.qza", emit: bins

    """
    qiime moshpit bin-contigs-metabat \
      --verbose \
      --p-seed 42 \
      --p-num-threads ${task.cpus} \
      --i-contigs ${contigs_file} \
      --i-alignment-maps ${maps_file} \
      --o-mags "paired-end-mags.qza"
    """
}

process EVALUATE_BINS {
    conda params.condaEnvPath
    cpus params.binning_qc.cpus
    // memory "${params.binning_qc.checkmReducedTree ? '16.GB' : '40.GB'}"
    // memory { (params.binning_qc.checkmReducedTree) ? '16GB' : '40GB' }
    // memory params.binning_qc.memory
    // memory { 16.GB }
    storeDir params.storeDir
    time params.binning_qc.time

    input:
    path bins_file

    output:
    path "paired-end-bins-qc.qzv"

    """
    qiime checkm evaluate-bins \
      --verbose \
      --p-threads ${task.cpus} \
      --p-pplacer-threads ${params.binning_qc.pplacerThreads} \
      --p-reduced-tree ${params.binning_qc.checkmReducedTree} \
      --p-db-path ${params.binning_qc.checkmDBpath} \
      --i-bins ${bins_file} \
      --o-visualization "paired-end-bins-qc.qzv"
    """
}
