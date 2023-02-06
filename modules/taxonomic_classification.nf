process CLASSIFY_BINS_KRAKEN2 {
    conda params.condaEnvPath
    cpus params.cpus
    memory { params.kraken2MemoryMapping ? 4.GB + 4.GB * task.attempt : 88.GB + 8.GB * task.attempt }
    storeDir params.storeDir

    errorStrategy "retry"
    maxRetries 3

    input:
    path bins_file

    output:
    path "paired-end-reads-kraken-reports.qza", emit: reports
    path "paired-end-reads-kraken-outputs.qza", emit: outputs

    """
    qiime moshpit classify-kraken \
      --verbose \
      --i-seqs ${bins_file} \
      --i-db ${params.kraken2DBpath} \
      --p-threads ${task.cpus} \
      --p-memory-mapping ${params.kraken2MemoryMapping} \
      --p-quick \
      --o-reports "paired-end-reads-kraken-reports.qza" \
      --o-outputs "paired-end-reads-kraken-outputs.qza"
    """
}

process CLASSIFY_READS_KRAKEN2 {
    conda params.condaEnvPath
    cpus params.cpus
    memory { params.kraken2MemoryMapping ? 4.GB + 4.GB * task.attempt : 88.GB + 8.GB * task.attempt }
    storeDir params.storeDir

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
      --i-db ${params.kraken2DBpath} \
      --p-threads ${task.cpus} \
      --p-memory-mapping ${params.kraken2MemoryMapping} \
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
