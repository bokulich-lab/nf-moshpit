process fetchGenomes {
    conda params.condaEnvPath
    storeDir params.storeDir

    output:
    file params.sampleGenomes

    """
    qiime rescript get-ncbi-genomes \
      --verbose \
      --p-taxon ${params.taxon} \
      --p-assembly-levels complete_genome \
      --p-assembly-source refseq \
      --o-genome-assemblies ${params.sampleGenomes} \
      --o-loci ${params.sampleLoci} \
      --o-proteins ${params.sampleProteins} \
      --o-taxonomies ${params.sampleTaxonomy}
    """
}

process simulateReads {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path genomes

    output:
    path params.filesReads, emit: reads
    path "output_genomes.qza", emit: genomes
    path "output_abundances.qza", emit: abundances

    """
    qiime assembly generate-reads \
      --i-genomes ${genomes} \
      --p-sample-names ${params.sampleNames} \
      --p-cpus ${task.cpus} \
      --p-n-genomes ${params.nGenomes} \
      --p-n-reads ${params.readCount} --p-seed 42 \
      --o-reads ${params.filesReads} \
      --o-template-genomes output_genomes.qza \
      --o-abundances output_abundances.qza
    """
}

process assembleMetaspades {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path reads_file

    output:
    path params.filesContigs

    """
    qiime assembly assemble-spades \
      --verbose \
      --i-seqs ${reads_file} \
      --p-meta --p-threads ${task.cpus} \
      --o-contigs ${params.filesContigs}
    """
}

process assembleMegahit {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    file reads_file

    output:
    file params.filesContigs

    """
    qiime assembly assemble-megahit \
      --verbose \
      --i-seqs ${reads_file} \
      --p-presets meta-sensitive --p-num-cpu-threads ${task.cpus} \
      --o-contigs ${params.filesContigs}
    """
}

process evaluateContigs {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path contigs_file
    path reads_file

    output:
    path "paired-end-contigs-qc.qzv"

    """
    qiime assembly evaluate-contigs \
      --verbose \
      --p-min-contig 100 \
      --i-contigs ${contigs_file} \
      --i-reads ${reads_file} --p-threads ${task.cpus} \
      --o-visualization paired-end-contigs-qc.qzv
    """
}

process indexContigs {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path contigs_file

    output:
    path params.filesIndex

    """
    qiime assembly index-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-contigs ${contigs_file} \
      --o-index ${params.filesIndex}
    """
}

process mapReadsToContigs {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path index_file
    path reads_file

    output:
    path params.filesAlnMap

    """
    qiime assembly map-reads-to-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-indexed-contigs ${index_file} \
      --i-reads ${reads_file} \
      --o-alignment-map ${params.filesAlnMap}
    """
}

process binContigs {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path contigs_file
    path maps_file

    output:
    path params.filesMags, emit: bins

    """
    qiime moshpit bin-contigs-metabat \
      --verbose \
      --p-seed 42 \
      --p-num-threads ${task.cpus} \
      --i-contigs ${contigs_file} \
      --i-alignment-maps ${maps_file} \
      --o-mags ${params.filesMags}
    """
}

process evaluateBins {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path bins_file

    output:
    path params.filesBinQCViz

    """
    qiime checkm evaluate-bins \
      --verbose \
      --p-threads ${task.cpus} \
      --p-pplacer-threads 4 \
      --p-reduced-tree \
      --p-db-path ${params.checkmDBpath} \
      --i-bins ${bins_file} \
      --o-visualization ${params.filesBinQCViz}
    """
}

process classifyBins {
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

process classifyReads {
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

process drawTaxaBarplot {
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
