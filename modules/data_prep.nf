process FETCH_GENOMES {
    conda params.condaEnvPath
    storeDir params.read_simulation.storeDir

    output:
    path params.read_simulation.sampleGenomes

    """
    qiime rescript get-ncbi-genomes \
      --verbose \
      --p-taxon ${params.read_simulation.taxon} \
      --p-assembly-levels complete_genome \
      --p-assembly-source refseq \
      --o-genome-assemblies ${params.read_simulation.sampleGenomes} \
      --o-loci "sample-loci.qza" \
      --o-proteins "sample-proteins.qza" \
      --o-taxonomies "sample-taxonomy.qza"
    """
}

process SIMULATE_READS {
    conda params.condaEnvPath
    cpus params.read_simulation.cpus
    storeDir params.read_simulation.storeDir
    time params.read_simulation.time

    input:
    path genomes

    output:
    path "reads.qza", emit: reads
    path "output-genomes.qza", emit: genomes
    path "output-abundances.qza", emit: abundances

    """
    qiime assembly generate-reads \
      --verbose \
      --i-genomes ${genomes} \
      --p-sample-names ${params.read_simulation.sampleNames} \
      --p-cpus ${task.cpus} \
      --p-n-genomes ${params.read_simulation.nGenomes} \
      --p-n-reads ${params.read_simulation.readCount} \
      --p-seed ${params.read_simulation.seed} \
      --p-abundance ${params.read_simulation.abundance} \
      --p-gc-bias ${params.read_simulation.gc_bias} \
      --o-reads "reads.qza" \
      --o-template-genomes output-genomes.qza \
      --o-abundances output-abundances.qza
    """
}

process FETCH_SEQS {
    conda params.condaEnvPath
    cpus params.fondue.cpus
    storeDir params.fondue.storeDir
    module "eth_proxy"
    time params.fondue.time

    input:
    path ids

    output:
    path "reads-single.qza", emit: single
    path "reads-paired.qza", emit: paired
    path "failed-runs.qza", emit: failed

    """
    if [ ! -d "$HOME/.ncbi" ]; then
        mkdir $HOME/.ncbi
        printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg
    elif [ ! -f "$HOME/.ncbi/user-settings.mkfg" ]; then
        printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg
    fi

    qiime fondue get-sequences \
      --verbose \
      --i-accession-ids ${ids} \
      --p-email ${params.email} \
      --p-n-jobs ${task.cpus} \
      --o-single-reads "reads-single.qza" \
      --o-paired-reads "reads-paired.qza" \
      --o-failed-runs "failed-runs.qza"
    """
}

process SUBSAMPLE_READS {
    conda params.condaEnvPath
    storeDir params.read_subsampling.storeDir
    time params.read_subsampling.time

    input:
    path reads, stageAs: 'reads'

    output:
    path reads_subsampled

    script:
    reads_subsampled = "reads-subsampled-${params.read_subsampling.fraction}.qza"
    if (params.read_subsampling.paired)
      """
      qiime demux subsample-paired \
        --verbose \
        --i-sequences ${reads}:${params.q2keyRawReads} \
        --p-fraction ${params.read_subsampling.fraction} \
        --o-subsampled-sequences ${reads_subsampled}
      """
    else
      """
      qiime demux subsample-single \
        --verbose \
        --i-sequences ${reads}:${params.q2keyRawReads} \
        --p-fraction ${params.read_subsampling.fraction} \
        --o-subsampled-sequences ${reads_subsampled}
      """
}

process SUMMARIZE_READS {
    conda params.condaEnvPath
    storeDir params.read_qc.storeDir
    time params.read_qc.time

    input:
    path reads, stageAs: 'reads'
    val suffix
    val q2key

    output:
    path "reads-qc-${suffix}.qzv"

    script:
    reads_path = (q2key == "") ? "${reads}" : "${reads}:${q2key}"
    """
    qiime demux summarize \
      --verbose \
      --i-data ${reads_path} \
      --p-n ${params.read_qc.n_reads} \
      --o-visualization reads-qc-${suffix}.qzv
    """
}

process TRIM_READS {
    conda params.condaEnvPath
    cpus params.read_trimming.cpus
    storeDir params.read_trimming.storeDir
    time params.read_trimming.time

    input:
    path reads, stageAs: 'reads'
    val q2key

    output:
    path reads_trimmed

    script:
    reads_path = (q2key == "") ? "${reads}" : "${reads}:${q2key}"
    reads_trimmed = params.read_trimming.paired ? "reads-paired-trimmed.qza" : "reads-single-trimmed.qza"
    if (params.read_trimming.paired)
      """
      qiime cutadapt trim-paired \
        --verbose \
        --i-demultiplexed-sequences ${reads_path} \
        --p-cores ${task.cpus} \
        --p-adapter-f ${params.read_trimming.adapter_f} \
        --p-front-f ${params.read_trimming.front_f} \
        --p-anywhere-f ${params.read_trimming.anywhere_f} \
        --p-adapter-r ${params.read_trimming.adapter_r} \
        --p-front-r ${params.read_trimming.front_r} \
        --p-anywhere-r ${params.read_trimming.anywhere_r} \
        --p-error-rate ${params.read_trimming.error_rate} \
        --p-indels ${params.read_trimming.indels} \
        --p-times ${params.read_trimming.times} \
        --p-overlap ${params.read_trimming.overlap} \
        --p-match-read-wildcards ${params.read_trimming.match_read_wildcards} \
        --p-match-adapter-wildcards ${params.read_trimming.match_adapter_wildcards} \
        --p-minimum-length ${params.read_trimming.minimum_length} \
        --p-discard-untrimmed ${params.read_trimming.discard_untrimmed} \
        --p-max-expected-errors ${params.read_trimming.max_expected_errors} \
        --p-max-n ${params.read_trimming.max_n} \
        --p-quality-cutoff-5end ${params.read_trimming.quality_cutoff_5end} \
        --p-quality-cutoff-3end ${params.read_trimming.quality_cutoff_3end} \
        --p-quality-base ${params.read_trimming.quality_base} \
        --o-trimmed-sequences ${reads_trimmed}
      """
    else
      """
      qiime cutadapt trim-single \
        --verbose \
        --i-demultiplexed-sequences ${reads_path} \
        --p-cores ${task.cpus} \
        --p-adapter ${params.read_trimming.adapter_f} \
        --p-front ${params.read_trimming.front_f} \
        --p-anywhere ${params.read_trimming.anywhere_f} \
        --p-error-rate ${params.read_trimming.error_rate} \
        --p-indels ${params.read_trimming.indels} \
        --p-times ${params.read_trimming.times} \
        --p-overlap ${params.read_trimming.overlap} \
        --p-match-read-wildcards ${params.read_trimming.match_read_wildcards} \
        --p-match-adapter-wildcards ${params.read_trimming.match_adapter_wildcards} \
        --p-minimum-length ${params.read_trimming.minimum_length} \
        --p-discard-untrimmed ${params.read_trimming.discard_untrimmed} \
        --p-max-expected-errors ${params.read_trimming.max_expected_errors} \
        --p-max-n ${params.read_trimming.max_n} \
        --p-quality-cutoff-5end ${params.read_trimming.quality_cutoff_5end} \
        --p-quality-cutoff-3end ${params.read_trimming.quality_cutoff_3end} \
        --p-quality-base ${params.read_trimming.quality_base} \
        --o-trimmed-sequences ${reads_trimmed}
      """
}

process REMOVE_HOST {
    conda params.condaEnvPath
    cpus params.host_removal.cpus
    storeDir params.host_removal.storeDir
    time params.host_removal.time

    input:
    path reads, stageAs: 'reads'

    output:
    path "reads-no-host.qza"

    script:
    reads_path = (params.read_subsampling.enabled || params.read_trimming.enabled) ? "${reads}" : "${reads}:${params.q2keyRawReads}"
    """
    qiime quality-control filter-reads \
      --verbose \
      --i-demultiplexed-sequences ${reads_path} \
      --i-database ${params.host_removal.database} \
      --p-n-threads ${task.cpus} \
      --p-mode ${params.host_removal.mode} \
      --p-sensitivity ${params.host_removal.sensitivity} \
      --p-ref-gap-open-penalty ${params.host_removal.ref_gap_open_penalty} \
      --p-ref-gap-ext-penalty ${params.host_removal.ref_gap_ext_penalty} \
      --p-exclude-seqs ${params.host_removal.exclude_seqs} \
      --o-filtered-sequences reads-no-host.qza
    """
}
