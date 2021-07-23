#!/usr/bin/env nextflow

process simulateReads {
    conda params.condaEnvPath
    cpus params.cpus

    input:
    file genomes from Channel.fromPath(params.genomes)

    output:
    file params.filesReads into readsAssemblyHit, readsAssemblySpades, readsEvalHit, readsEvalSpades
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

process assembleMegahit {
    conda params.condaEnvPath
    cpus params.cpus

    input:
    file reads_file from readsAssemblyHit

    output:
    file params.filesContigsHit into contigsHit, contigsHitInd

    """
    qiime assembly assemble-megahit \
      --verbose \
      --i-seqs ${reads_file} \
      --p-presets meta-sensitive --p-num-cpu-threads ${task.cpus} \
      --o-contigs ${params.filesContigsHit}
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

process evaluateContigsHit {
    conda params.condaEnvPath

    input:
    file contigs_file from contigsHit
    file reads_file from readsEvalHit

    output:
    path("paired-end-megahit-qc.qzv")

    """
    qiime assembly evaluate-contigs \
      --verbose \
      --p-min-contig 100 \
      --i-contigs ${contigs_file} \
      --i-reads ${reads_file} --p-threads 1 \
      --o-visualization paired-end-megahit-qc.qzv
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

process indexContigsHit {
    conda params.condaEnvPath
    cpus params.cpus

    input:
    file contigs_file from contigsHitInd

    output:
    file params.filesIndexHit into indexHit

    """
    qiime assembly index-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-contigs ${contigs_file} \
      --o-index ${params.filesIndexHit}
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

// result.view { it.trim() }
