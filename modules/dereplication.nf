process CALCULATE_MINHASHES {
    conda params.condaEnvPath
    storeDir params.storeDir
    time params.dereplication.sourmash.time
    clusterOptions "--mem-per-cpu=${params.dereplication.sourmash.memoryPerCPU} ${params.dereplication.sourmash.clusterOptions}"

    input:
    path bins_file

    output:
    path "mags-minhash.qza"

    script:
    """
    qiime sourmash compute \
      --verbose \
      --p-ksizes ${params.dereplication.sourmash.ksizes} \
      --p-scaled ${params.dereplication.sourmash.scaled} \
      --p-track-abundance ${params.dereplication.sourmash.trackAbundance} \
      --i-sequence-file ${bins_file} \
      --o-min-hash-signature "mags-minhash.qza"
    """
}

process COMPARE_MINHASHES {
    conda params.condaEnvPath
    storeDir params.storeDir
    time params.dereplication.sourmash.time
    clusterOptions "--mem-per-cpu=${params.dereplication.sourmash.memoryPerCPU} ${params.dereplication.sourmash.clusterOptions}"

    input:
    path hashes_file

    output:
    path "mags-dist-matrix.qza"

    script:
    ignore_abundance = params.dereplication.sourmash.trackAbundance ? false : true
    """
    qiime sourmash compare \
      --verbose \
      --p-ksize ${params.dereplication.sourmash.ksizes} \
      --p-ignore-abundance ${ignore_abundance} \
      --i-min-hash-signature ${hashes_file} \
      --o-compare-output "mags-dist-matrix.qza"
    """
}

process DEREPLICATE_MAGS {
    conda params.condaEnvPath
    storeDir params.storeDir
    time params.dereplication.time
    clusterOptions "--mem-per-cpu=${params.dereplication.memoryPerCPU} ${params.dereplication.clusterOptions}"

    input:
    path bins_file
    path distance_matrix

    output:
    path "mags-dereplicated.qza", emit: bins_derep
    path "mags-pa-table.qza", emit: feature_table

    script:
    """
    qiime moshpit dereplicate-mags \
      --verbose \
      --p-threshold ${params.dereplication.threshold} \
      --i-mags ${bins_file} \
      --i-distance-matrix ${distance_matrix} \
      --o-dereplicated-mags "mags-dereplicated.qza" \
      --o-feature-table "mags-pa-table.qza"
    """
}
