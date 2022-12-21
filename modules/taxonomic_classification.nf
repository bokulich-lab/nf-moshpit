process CLASSIFY_BINS_KRAKEN2 {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path bins_file

    output:
    path params.filesBinTable, emit: table
    path params.filesBinTaxonomy, emit: taxonomy
    path params.filesBinKrakenReports, emit: reports

    """
    qiime moshpit classify-kraken \
      --verbose \
      --i-seqs ${bins_file} \
      --p-db ${params.kraken2DBpath} \
      --p-threads ${task.cpus} \
      --p-memory-mapping \
      --p-quick \
      --o-table ${params.filesBinTable} \
      --o-taxonomy ${params.filesBinTaxonomy} \
      --o-reports ${params.filesBinKrakenReports}
    """
}

process CLASSIFY_READS_KRAKEN2 {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path reads_file

    output:
    path params.filesReadsTable, emit: table
    path params.filesReadsTaxonomy, emit: taxonomy
    path params.filesReadsKrakenReports, emit: reports

    """
    qiime moshpit classify-kraken \
      --verbose \
      --i-seqs ${reads_file} \
      --p-db ${params.kraken2DBpath} \
      --p-threads ${task.cpus} \
      --p-memory-mapping \
      --p-quick \
      --o-table ${params.filesReadsTable} \
      --o-taxonomy ${params.filesReadsTaxonomy} \
      --o-reports ${params.filesReadsKrakenReports}
    """
}

process DRAW_TAXA_BARPLOT {
    conda params.condaEnvPath
    storeDir params.storeDir

    input:
    path feature_table
    path taxonomy

    output:
    path params.filesBinKrakenBarplots

    """
    qiime taxa barplot \
      --verbose \
      --i-table ${feature_table} \
      --i-taxonomy ${taxonomy} \
      --o-visualization ${params.filesBinKrakenBarplots}
    """
}
