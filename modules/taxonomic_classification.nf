process CLASSIFY_BINS_KRAKEN2 {
    conda params.condaEnvPath
    // cpus params.taxonomic_classification.cpus
    // memory { params.kraken2MemoryMapping == true ? 4.GB + 4.GB * task.attempt : 88.GB + 8.GB * task.attempt }
    clusterOptions params.taxonomic_classification.clusterOptions
    storeDir params.storeDir
    time params.taxonomic_classification.time
    errorStrategy "retry"
    maxRetries 3

    input:
    path bins_file

    output:
    path reports, emit: reports
    path outputs, emit: outputs

    script:
    reports = "bins-kraken-reports.qza"
    outputs = "bins-kraken-outputs.qza"
    """
    qiime moshpit classify-kraken \
      --verbose \
      --i-seqs ${bins_file} \
      --i-db ${params.taxonomic_classification.kraken2DBpath} \
      --p-threads ${params.taxonomic_classification.cpus} \
      --p-memory-mapping ${params.taxonomic_classification.kraken2MemoryMapping} \
      --p-quick \
      --o-reports ${reports} \
      --o-outputs ${outputs}
    """
}

process CLASSIFY_READS_KRAKEN2 {
    conda params.condaEnvPath
    // cpus params.taxonomic_classification.cpus
    // memory { 88.GB + 8.GB * task.attempt }
    clusterOptions params.taxonomic_classification.clusterOptions
    storeDir params.storeDir
    time params.taxonomic_classification.time

    errorStrategy "retry"
    maxRetries 3

    input:
    path reads_file

    output:
    path reports, emit: reports
    path outputs, emit: outputs

    script:
    reports = "reads-kraken-reports.qza"
    outputs = "reads-kraken-outputs.qza"
    """
    qiime moshpit classify-kraken \
      --verbose \
      --i-seqs ${reads_file} \
      --i-db ${params.taxonomic_classification.kraken2DBpath} \
      --p-threads ${params.taxonomic_classification.cpus} \
      --p-memory-mapping ${params.taxonomic_classification.kraken2MemoryMapping} \
      --p-quick \
      --o-reports ${reports} \
      --o-outputs ${outputs}
    """
}

process DRAW_TAXA_BARPLOT {
    conda params.condaEnvPath
    storeDir params.storeDir

    input:
    path feature_table
    path taxonomy

    output:
    path "kraken-barplot.qzv"

    script:
    """
    qiime taxa barplot \
      --verbose \
      --i-table ${feature_table} \
      --i-taxonomy ${taxonomy} \
      --o-visualization "kraken-barplot.qzv"
    """
}
