process ASSEMBLE_METASPADES {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path reads_file

    output:
    path "paired-end-contigs.qza"

    """
    qiime assembly assemble-spades \
      --verbose \
      --i-seqs ${reads_file} \
      --p-meta --p-threads ${task.cpus} \
      --o-contigs "paired-end-contigs.qza"
    """
}

process ASSEMBLE_MEGAHIT {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    file reads_file

    output:
    file "paired-end-contigs.qza"

    """
    qiime assembly assemble-megahit \
      --verbose \
      --i-seqs ${reads_file} \
      --p-presets meta-sensitive --p-num-cpu-threads ${task.cpus} \
      --o-contigs "paired-end-contigs.qza"
    """
}

process EVALUATE_CONTIGS {
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

process INDEX_CONTIGS {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path contigs_file

    output:
    path "paired-end-index.qza"

    """
    qiime assembly index-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-contigs ${contigs_file} \
      --o-index "paired-end-index.qza"
    """
}

process MAP_READS_TO_CONTIGS {
    conda params.condaEnvPath
    cpus params.cpus
    storeDir params.storeDir

    input:
    path index_file
    path reads_file

    output:
    path "paired-end-bowtie-map-contigs.qza"

    """
    qiime assembly map-reads-to-contigs \
      --verbose \
      --p-seed 42 \
      --p-threads ${task.cpus} \
      --i-indexed-contigs ${index_file} \
      --i-reads ${reads_file} \
      --o-alignment-map "paired-end-bowtie-map-contigs.qza"
    """
}
