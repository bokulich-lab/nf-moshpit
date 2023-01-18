process CLASSIFY_BINS_KRAKEN2 {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path bins_file

    output:
    path params.filesBinKrakenReports, emit: reports
    path params.filesBinKrakenOutputs, emit: outputs

    """
    qiime moshpit classify-kraken \
      --verbose \
      --i-seqs ${bins_file} \
      --i-db ${params.kraken2DBpath} \
      --p-threads ${task.cpus} \
      --p-memory-mapping \
      --p-quick \
      --o-reports ${params.filesBinKrakenReports} \
      --o-outputs ${params.filesBinKrakenOutputs}
    """
}

process CLASSIFY_READS_KRAKEN2 {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path reads_file

    output:
    path params.filesReadsKrakenReports, emit: reports
    path params.filesReadsKrakenOutputs, emit: outputs

    """
    qiime moshpit classify-kraken \
      --verbose \
      --i-seqs ${reads_file} \
      --i-db ${params.kraken2DBpath} \
      --p-threads ${task.cpus} \
      --p-memory-mapping \
      --p-quick \
      --o-reports ${params.filesReadsKrakenReports} \
      --o-outputs ${params.filesReadsKrakenOutputs}
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
