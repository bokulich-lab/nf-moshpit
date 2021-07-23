#!/usr/bin/env nextflow

process simulateReads {
    conda params.condaEnvPath
    cpus params.cpus

    input:
    file genomes from Channel.fromPath(params.genomes)

    output:
    file params.filesReads into readsAssemblySpades, readsEvalSpades
    file "output_genomes.qza" into outputGenomes
    file "output_abundances.qza" into outputAbundances

    """
    qiime assembly generate-reads \
      --i-genomes ${params.genomes} \
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

    input:
    file reads_file from readsAssemblySpades

    output:
    file params.filesContigsSpades into contigsSpades, contigsSpadesInd

    """
    qiime assembly assemble-spades \
      --verbose \
      --i-seqs ${reads_file} \
      --p-meta --p-threads ${task.cpus} \
      --o-contigs ${params.filesContigsSpades}
    """
}

process evaluateContigsSpades {
    conda params.condaEnvPath

    input:
    file contigs_file from contigsSpades
    file reads_file from readsEvalSpades

    output:
    path("paired-end-metaspades-qc.qzv")

    """
    qiime assembly evaluate-contigs \
      --verbose \
      --p-min-contig 100 \
      --i-contigs ${contigs_file} \
      --i-reads ${reads_file} --p-threads 1 \
      --o-visualization paired-end-metaspades-qc.qzv
    """
}

process indexContigsSpades {
    conda params.condaEnvPath
    cpus params.cpus

    input:
    file contigs_file from contigsSpadesInd

    output:
    file params.filesIndexSpades into indexSpades

    """
    qiime assembly index-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-contigs ${contigs_file} \
      --o-index ${params.filesIndexSpades}
    """
}
