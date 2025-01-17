process FETCH_GENOMES {
    label "needsInternet"

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
    cpus 1

    input:
    tuple val(_id), path(reads)
    path q2_cache

    output:
    tuple val(_id), path(reads_subsampled)

    script:
    reads_subsampled = "reads_subsampled_${params.read_subsampling.fraction.toString().replace(".", "_")}_${_id}"
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

process PROCESS_READS_FASTP {
    label "fastp"

    input:
    tuple val(_id), path(reads)
    path q2_cache

    output:
    tuple val(_id), path(key_reads), path(key_reports)

    script:
    key_reads = "reads_fastp_${_id}"
    key_reports = "fastp_report_${_id}"
    qc_filtering_flag = params.read_qc.fastp.disableQualityFiltering ? "--p-disable-quality-filtering" : "--p-no-disable-quality-filtering"
    dedup_flag = params.read_qc.fastp.deduplicate ? "--p-dedup" : "--p-no-dedup"
    adapter_trimming_flag = params.read_qc.fastp.disableAdapterTrimming ? "--p-disable-adapter-trimming" : "--p-no-disable-adapter-trimming"
    correction_flag = params.read_qc.fastp.enableBaseCorrection ? "--p-correction" : "--p-no-correction"
    """
    qiime fastp process-seqs \
      --verbose \
      --i-sequences ${params.q2cacheDir}:${reads} \
      ${qc_filtering_flag} \
      ${dedup_flag} \
      ${adapter_trimming_flag} \
      ${correction_flag} \
      ${params.read_qc.fastp.additionalFlags} \
      --p-thread ${task.cpus} \
      --o-processed-sequences ${params.q2cacheDir}:${key_reads} \
      --o-reports ${params.q2cacheDir}:${key_reports} \
    && touch ${key_reads} \
    && touch ${key_reports}
    """
}

process VISUALIZE_FASTP {
    cpus 1
    memory 1.GB
    publishDir params.publishDir, mode: 'copy'

    input:
    path fastp_reports
    path q2_cache

    output:
    path "reads-qc-fastp.qzv"

    script:
    """
    qiime fastp visualize \
      --verbose \
      --i-reports ${params.q2cacheDir}:${fastp_reports} \
      --o-visualization reads-qc-fastp.qzv
    """
}

process REMOVE_HOST {
    label "hostRemoval"
    label "needsInternet"
    errorStrategy { task.exitStatus == 137 ? 'retry' : 'terminate' } 
    maxRetries 3
    
    input:
    tuple val(sample_id), path(reads)
    path q2_cache

    output:
    tuple val(sample_id), path(key), emit: reads
    path "human_reference_index", emit: reference

    script:
    index_flag = params.host_removal.database.key ? "--i-index ${params.host_removal.database.cache}:${params.host_removal.database.key}" : ""
    key = "reads_no_host_partitioned_${sample_id}"
    """
    qiime moshpit filter-reads-pangenome \
      --verbose \
      --i-reads ${params.q2cacheDir}:${reads} \
      --p-n-threads ${task.cpus} \
      --p-mode ${params.host_removal.mode} \
      --p-sensitivity ${params.host_removal.sensitivity} \
      --p-ref-gap-open-penalty ${params.host_removal.ref_gap_open_penalty} \
      --p-ref-gap-ext-penalty ${params.host_removal.ref_gap_ext_penalty} \
      --o-filtered-reads ${params.q2cacheDir}:${key} \
      ${index_flag} \
      --o-reference-index ${params.host_removal.database.cache}:human_reference_index > output.log 2>&1 \
      && touch ${key} \
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
    publishDir params.publishDir, mode: 'copy'

    input:
    val cache_key
    
    output:
    path artifact_name

    script:
    cache_key = new File(cache_key.toString()).getName();
    artifact_name = cache_key.replace("_", "-") + ".qza"
    """
    qiime tools cache-fetch \
      --cache ${params.q2cacheDir} \
      --key ${cache_key} \
      --output-path ${artifact_name}
    """
}

process PARTITION_ARTIFACT {
    cpus 1

    input:
    path cache_key
    val prefix
    val qiime_action
    val qiime_input_flag
    val qiime_output_flag

    output:
    path "${prefix}*"

    script:
    """
    if [ ! -f "${params.q2cacheDir}/keys/${prefix}collection" ]; then
      qiime ${qiime_action} \
      ${qiime_input_flag} ${params.q2cacheDir}:${cache_key} \
      ${qiime_output_flag} ${params.q2cacheDir}:${prefix}collection
    else
      echo "The ${prefix}collection result collection already exists and will not be recreated."
    fi

    bash ${projectDir}/../scripts/partition.sh \
      -i ${params.q2cacheDir}/keys/${prefix}collection \
      -d ${params.q2cacheDir}/keys \
      -p ${prefix} \
      -s
    """
}

process COLLATE_PARTITIONS {
    cpus 1
    memory 4.GB

    input:
    path cache_key_in
    val cache_key_out 
    val qiime_action
    val qiime_input_flag
    val qiime_output_flag
    val clean_up

    output:
    path "${cache_key_out}"

    script:
    """
    keys_in=\$(for path in ${cache_key_in}; do echo "${params.q2cacheDir}:\$(basename "\$path")"; done)
    echo \$keys_in
    qiime ${qiime_action} \
      ${qiime_input_flag} \$keys_in \
      ${qiime_output_flag} ${params.q2cacheDir}:${cache_key_out} \
    && touch ${cache_key_out}
    """

    // if (clean_up === true) {
    //   """
    //   qiime tools cache-remove --cache ${params.q2cacheDir} --key ${prefix}_collection
    //   """
    // }
}

process TABULATE_READ_COUNTS {
    storeDir params.storeDir
    maxRetries 3 
    
    input:
    path reads
    path q2_cache

    output:
    path "reads_counts"

    script:
    """
    qiime demux tabulate-read-counts \
      --verbose \
      --i-sequences ${params.q2cacheDir}:${reads} \
      --o-counts ${params.q2cacheDir}:reads_counts \
      && touch reads_counts
    """
}

process FILTER_SAMPLES {
    storeDir params.storeDir
    
    input:
    path reads
    path metadata
    val query
    path q2_cache

    output:
    path "reads_filtered"

    script:
    """
    qiime demux filter-samples \
      --verbose \
      --i-demux ${params.q2cacheDir}:${reads} \
      --m-metadata-file ${params.q2cacheDir}:${metadata} \
      --p-where ${query} \
      --o-filtered-demux ${params.q2cacheDir}:reads_filtered \
      && touch reads_filtered
    """
}
