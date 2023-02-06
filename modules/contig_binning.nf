process BIN_CONTIGS_METABAT {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

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
    cpus params.cpus
    memory { params.checkmReducedTree ? 16.GB : 40.GB }
    storeDir params.storeDir

    input:
    path bins_file

    output:
    path "paired-end-bins-qc.qzv"

    """
    qiime checkm evaluate-bins \
      --verbose \
      --p-threads ${task.cpus} \
      --p-pplacer-threads 4 \
      --p-reduced-tree ${params.checkmReducedTree} \
      --p-db-path ${params.checkmDBpath} \
      --i-bins ${bins_file} \
      --o-visualization "paired-end-bins-qc.qzv"
    """
}
