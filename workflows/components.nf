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
      --i-reads ${reads_file} --p-threads 1 \
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
    path params.filesMags

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
    qiime moshpit evaluate-bins \
      --verbose \
      --p-threads ${task.cpus} \
      --p-pplacer-threads 4 \
      --p-reduced-tree \
      --p-db-path ${params.checkmDBpath} \
      --i-bins ${bins_file} \
      --o-visualization ${params.filesBinQCViz}
    """
}
