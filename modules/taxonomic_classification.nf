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
    path "paired-end-mags-kraken-reports.qza", emit: reports
    path "paired-end-mags-kraken-outputs.qza", emit: outputs

    """
    qiime moshpit classify-kraken \
      --verbose \
      --i-seqs ${bins_file} \
      --i-db ${params.taxonomic_classification.kraken2DBpath} \
      --p-threads ${params.taxonomic_classification.cpus} \
      --p-memory-mapping ${params.taxonomic_classification.kraken2MemoryMapping} \
      --p-quick \
      --o-reports "paired-end-mags-kraken-reports.qza" \
      --o-outputs "paired-end-mags-kraken-outputs.qza"
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
    path "paired-end-reads-kraken-reports.qza", emit: reports
    path "paired-end-reads-kraken-outputs.qza", emit: outputs

    """
    qiime moshpit classify-kraken \
      --verbose \
      --i-seqs ${reads_file} \
      --i-db ${params.taxonomic_classification.kraken2DBpath} \
      --p-threads ${params.taxonomic_classification.cpus} \
      --p-memory-mapping ${params.taxonomic_classification.kraken2MemoryMapping} \
      --p-quick \
      --o-reports "paired-end-reads-kraken-reports.qza" \
      --o-outputs "paired-end-reads-kraken-outputs.qza"
    """
}

process DRAW_TAXA_BARPLOT {
    conda params.condaEnvPath
    storeDir params.storeDir

    input:
    path feature_table
    path taxonomy

    output:
    path "paired-end-reads-kraken.qzv"

    """
    qiime taxa barplot \
      --verbose \
      --i-table ${feature_table} \
      --i-taxonomy ${taxonomy} \
      --o-visualization "paired-end-reads-kraken.qzv"
    """
}
