process FETCH_GENOMES {
    label "needsInternet"
    storeDir params.storeDir

    input:
    path q2_cache

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
    label "readSimulation"
    storeDir params.storeDir

    input:
    path genomes
    path q2_cache

    output:
    path "reads", emit: reads
    path "output_genomes", emit: genomes
    path "output_abundances", emit: abundances

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
      --o-reads ${params.q2cacheDir}:reads \
      --o-template-genomes ${params.q2cacheDir}:output_genomes \
      --o-abundances ${params.q2cacheDir}:output_abundances \
    && touch reads \
    && touch output_genomes \
    && touch output_abundances
    """
}

process FETCH_SEQS {
    label "fondue"
    label "needsInternet"
    storeDir params.storeDir

    input:
    path ids
    path q2_cache

    output:
    path "reads_single", emit: single
    path "reads_paired", emit: paired
    path "failed_runs", emit: failed

    script:
    """
    if [ ! -d "$HOME/.ncbi" ]; then
        echo 'Directory $HOME/.ncbi does not exist and will be created'
        mkdir $HOME/.ncbi
        echo 'Creating SRA Toolkit config file in $HOME/.ncbi/user-settings.mkfg'
        printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg
    elif [ ! -f "$HOME/.ncbi/user-settings.mkfg" ]; then
        echo 'Creating SRA Toolkit config file in $HOME/.ncbi/user-settings.mkfg'
        printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg
    else
        echo 'NCBI config files exist - we will attempt to copy the config into the QIIME 2 home directory.'
        if [ -d "/home/qiime2" ]; then
          mkdir -p /home/qiime2/.ncbi
          cp $HOME/.ncbi/user-settings.mkfg /home/qiime2/.ncbi/user-settings.mkfg
          ls /home/qiime2/.ncbi
          echo "Success - required config files were created."
        else
          echo "The directory /home/qiime2 does not exist - are you running the pipeline using a Singularity container?"
          exit 1
        fi
    fi

    qiime fondue get-sequences \
      --verbose \
      --i-accession-ids ${ids} \
      --p-email ${params.email} \
      --p-n-jobs ${task.cpus} \
      --o-single-reads ${params.q2cacheDir}:reads_single \
      --o-paired-reads ${params.q2cacheDir}:reads_paired \
      --o-failed-runs ${params.q2cacheDir}:failed_runs \
    && touch reads_single \
    && touch reads_paired \
    && touch failed_runs
    """
}

process SUBSAMPLE_READS {
    label "readSubsampling"
    storeDir params.storeDir
    cpus 1

    input:
    path reads
    path q2_cache

    output:
    path reads_subsampled

    script:
    reads_subsampled = "reads_subsampled_${params.read_subsampling.fraction}"

    if (params.read_subsampling.paired) {
      """
      qiime demux subsample-paired \
        --verbose \
        --i-sequences ${params.q2cacheDir}:${reads} \
        --p-fraction ${params.read_subsampling.fraction} \
        --o-subsampled-sequences ${params.q2cacheDir}:${reads_subsampled} \
      && touch ${reads_subsampled}
      """
    } else {
      """
      qiime demux subsample-single \
        --verbose \
        --i-sequences ${params.q2cacheDir}:${reads} \
        --p-fraction ${params.read_subsampling.fraction} \
        --o-subsampled-sequences ${params.q2cacheDir}:${reads_subsampled} \
      && touch ${reads_subsampled}
      """
  }
}

process SUMMARIZE_READS {
    storeDir params.storeDir
    publishDir params.publishDir, mode: 'copy'
    cpus 1

    input:
    path reads
    val suffix
    path q2_cache

    output:
    path "reads-qc-${suffix}.qzv"

    script:
    """
    qiime demux summarize \
      --verbose \
      --i-data ${params.q2cacheDir}:${reads} \
      --p-n ${params.read_qc.n_reads} \
      --o-visualization reads-qc-${suffix}.qzv
    """
}

process TRIM_READS {
    label "readTrimming"
    storeDir params.storeDir

    input:
    path reads
    path q2_cache

    output:
    path reads_trimmed

    script:
    reads_trimmed = params.read_trimming.paired ? "reads_paired_trimmed" : "reads_single_trimmed"

    if (params.read_trimming.paired) {
      """
      qiime cutadapt trim-paired \
        --verbose \
        --i-demultiplexed-sequences ${params.q2cacheDir}:${reads} \
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
        --o-trimmed-sequences ${params.q2cacheDir}:${reads_trimmed} \
      && touch ${reads_trimmed}
      """
    } else {
      """
      qiime cutadapt trim-single \
        --verbose \
        --i-demultiplexed-sequences ${params.q2cacheDir}:${reads} \
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
        --o-trimmed-sequences ${params.q2cacheDir}:${reads_trimmed} \
      && touch ${reads_trimmed}
      """
    }
}

process REMOVE_HOST {
    label "hostRemoval"
    label "needsInternet"
    storeDir params.storeDir
    errorStrategy { task.exitStatus == 137 ? 'retry' : 'terminate' } 
    maxRetries 3 
    
    input:
    path reads
    path q2_cache

    output:
    path "reads_no_host", emit: reads
    path "human_reference_index", emit: reference

    script:
    index_flag = params.host_removal.database.key ? "--i-index ${params.host_removal.database.cache}:${params.host_removal.database.key}" : ""
    
    """
    qiime moshpit filter-reads-pangenome \
      --verbose \
      --i-reads ${params.q2cacheDir}:${reads} \
      --p-n-threads ${task.cpus} \
      --p-mode ${params.host_removal.mode} \
      --p-sensitivity ${params.host_removal.sensitivity} \
      --p-ref-gap-open-penalty ${params.host_removal.ref_gap_open_penalty} \
      --p-ref-gap-ext-penalty ${params.host_removal.ref_gap_ext_penalty} \
      --o-filtered-reads ${params.q2cacheDir}:reads_no_host \
      ${index_flag} \
      --o-reference-index ${params.host_removal.database.cache}:human_reference_index > output.log 2>&1 \
      && touch reads_no_host \
      && touch human_reference_index
    """

}

process INIT_CACHE {

    output:
    path "cache.txt"

    script:
    if (params.q2cacheDirExists == "ok"){
      """
      qiime tools cache-create --cache ${params.q2cacheDir}
      echo ${params.q2cacheDir} > cache.txt
      """
    } else {
      """
      if [ -d "${params.q2cacheDir}" ]; then
        echo "Indicated QIIME 2 cache directory exists. Exiting."
        exit 1
      else
        qiime tools cache-create --cache ${params.q2cacheDir}
        echo ${params.q2cacheDir} > cache.txt
      fi
      """
    }
    
}

process FETCH_ARTIFACT {
    storeDir params.storeDir
    publishDir params.publishDir, mode: 'move'

    input:
    val cache_key
    val artifact_name
    
    output:
    path "${artifact_name}"

    script:
    cache_key = new File(cache_key.toString()).getName();
    """
    qiime tools cache-fetch \
      --cache ${params.q2cacheDir} \
      --key ${cache_key} \
      --output-path ${artifact_name}
    """
}
