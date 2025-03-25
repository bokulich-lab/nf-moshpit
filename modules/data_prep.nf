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
    path "${params.runId}_reads", emit: reads
    path "${params.runId}_output_genomes", emit: genomes
    path "${params.runId}_output_abundances", emit: abundances

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
      --o-reads ${params.q2cacheDir}:${params.runId}_reads \
      --o-template-genomes ${params.q2cacheDir}:${params.runId}_output_genomes \
      --o-abundances ${params.q2cacheDir}:${params.runId}_output_abundances \
    && touch ${params.runId}_reads \
    && touch ${params.runId}_output_genomes \
    && touch ${params.runId}_output_abundances
    """
}

process FETCH_SEQS {
    label "fondue"
    label "needsInternet"
    scratch true
    tag "${_id}"
    errorStrategy { task.exitStatus in [125, 126] ? 'ignore' : 'retry' }
    maxRetries 3

    input:
    val _id
    // path q2_cache

    output:
    tuple val(_id), path(reads_single), emit: single
    tuple val(_id), path(reads_paired), emit: paired
    tuple val(_id), path(failed_runs), emit: failed

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
    reads_paired = "${params.runId}_reads_paired_${_id}"
    reads_single = "${params.runId}_reads_single_${_id}"
    failed_runs = "${params.runId}_failed_runs_${_id}"
    """
    qiime tools cache-create --cache ${q2cacheDir}

    if [ -f ${q2cacheDir}/keys/${reads_paired} ] && [ -f ${q2cacheDir}/keys/${reads_single} ] && [ -f ${q2cacheDir}/keys/${failed_runs} ]; then
      echo "All cache keys exist for sample ${_id}"
      touch ${reads_paired} && touch ${reads_single} && touch ${failed_runs}
      exit 0
    fi

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

    echo -e "id\n${_id}" > ids.tsv

    echo "Importing IDs into an artifact..."

    qiime tools import \
      --type NCBIAccessionIDs \
      --input-path ids.tsv \
      --output-path ids.qza

    echo "Starting data fetch..."

    set +e
    qiime fondue get-sequences \
      --verbose \
      --i-accession-ids ids.qza \
      --p-email ${params.email} \
      --p-n-jobs ${task.cpus} \
      --o-single-reads ${q2cacheDir}:${reads_single} \
      --o-paired-reads ${q2cacheDir}:${reads_paired} \
      --o-failed-runs ${q2cacheDir}:${failed_runs} > output.txt 2> error.txt

    qiime_exit_code=\$?
    echo "QIIME exit code: \$qiime_exit_code"
    set -e

    if [ \$qiime_exit_code -eq 0 ]; then
      count=\$(ls ${q2cacheDir}/keys/ | grep -E '${reads_paired}|${reads_single}|${failed_runs}' | wc -l)
      echo "File count is: \$count."
      if [ "\$count" -ne 3 ]; then
        echo "Some of the required keys are missing in the cache."
        exit 1
      fi
    fi
    
    cat output.txt >> .command.out
    cat error.txt >> .command.err

    if grep -q "Neither single- nor paired-end sequences could be downloaded" output.txt || grep -q "Neither single- nor paired-end sequences could be downloaded" error.txt; then
      echo "Neither single- nor paired-end sequences could be downloaded."
      exit 125
    elif grep -q "Already unlocked" output.txt || grep -q "Already unlocked" error.txt; then
      echo "Already unlocked error - please investigate the full log."
      echo "This error will be ignored since all the required keys are present in the cache."
      qiime_exit_code=0
    fi

    if [[ ${params.fondue.paired} == 'true' ]]; then
      key=${reads_paired}
    else
      key=${reads_single}
    fi

    uuid=\$(cat ${q2cacheDir}/keys/\$key | grep 'data' | awk '{print \$2}')
    paths=\$(ls ${q2cacheDir}/data/\$uuid/data | grep 'fastq')
    echo "Samples found: \$paths"
    
    if [[ \$paths == *"xxx_"* ]]; then
      echo "Empty sample found for key \$key"
      exit 125
    else
      echo "No empty samples found for key \$key"
    fi

    touch ${reads_paired} && touch ${reads_single} && touch ${failed_runs}

    exit \$qiime_exit_code
    """
}


// process FILTER_EMPTY_SEQS {
//     scratch true
//     tag "${_id}"
//     errorStrategy { task.exitStatus == 125 ? 'ignore' : 'terminate' }

//     input:
//     tuple val(_id), path(key)
//     path q2_cache

//     output:
//     tuple val(_id), path(key)

//     script:
//     """
//     uuid=\$(cat ${params.q2cacheDir}/keys/${key} | grep 'data' | awk '{print \$2}')
//     paths=\$(ls ${params.q2cacheDir}/data/\$uuid/data | grep 'fastq')
//     echo "Samples found: \$paths"
    
//     if [[ \$paths == *"xxx_"* ]]; then
//       echo "Empty sample found for key ${key}"
//       exit 125
//     else
//       echo "No empty samples found for key ${key}"
//       touch ${key}
//       exit 0
//     fi
//     """
// }

process SUBSAMPLE_READS {
    label "readSubsampling"
    storeDir params.storeDir
    cpus 1
    scratch true
    tag "${sample_id}"

    input:
    tuple val(sample_id), path(reads)
    path q2_cache

    output:
    tuple val(sample_id), path(reads_subsampled)

    script:
    reads_subsampled = "${params.runId}_reads_subsampled_${params.read_subsampling.fraction.toString().replace(".", "_")}_${sample_id}"
    if (params.read_subsampling.paired) {
      """
      echo Processing sample ${sample_id}
      qiime demux subsample-paired \
        --verbose \
        --i-sequences ${params.q2cacheDir}:${reads} \
        --p-fraction ${params.read_subsampling.fraction} \
        --o-subsampled-sequences ${params.q2cacheDir}:${reads_subsampled} \
      && touch ${reads_subsampled}
      """
    } else {
      """
      echo Processing sample ${sample_id}
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
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    errorStrategy { task.exitStatus in [125, 126] ? 'ignore' : 'retry' }
    maxRetries 3

    input:
    tuple val(sample_id), path(reads)
    // path q2_cache

    output:
    tuple val(sample_id), path(key_reads), path(key_reports)

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    key_reads = "${params.runId}_reads_fastp_${sample_id}"
    key_reports = "${params.runId}_fastp_report_${sample_id}"
    qc_filtering_flag = params.read_qc.fastp.disableQualityFiltering ? "--p-disable-quality-filtering" : "--p-no-disable-quality-filtering"
    dedup_flag = params.read_qc.fastp.deduplicate ? "--p-dedup" : "--p-no-dedup"
    adapter_trimming_flag = params.read_qc.fastp.disableAdapterTrimming ? "--p-disable-adapter-trimming" : "--p-no-disable-adapter-trimming"
    correction_flag = params.read_qc.fastp.enableBaseCorrection ? "--p-correction" : "--p-no-correction"
    """
    echo Processing sample ${sample_id}

    set +e
    qiime fastp process-seqs \
      --verbose \
      --i-sequences ${q2cacheDir}:${reads} \
      ${qc_filtering_flag} \
      ${dedup_flag} \
      ${adapter_trimming_flag} \
      ${correction_flag} \
      ${params.read_qc.fastp.additionalFlags} \
      --p-thread ${task.cpus} \
      --o-processed-sequences ${q2cacheDir}:${key_reads} \
      --o-reports ${q2cacheDir}:${key_reports} > output.txt 2> error.txt

    qiime_exit_code=\$?
    echo "QIIME exit code: \$qiime_exit_code"
    set -e

    cat output.txt >> .command.out
    cat error.txt >> .command.err

    if [ \$qiime_exit_code -eq 0 ]; then
      count=\$(ls ${q2cacheDir}/keys/ | grep -E '${key_reads}|${key_reports}' | wc -l)
      echo "File count is: \$count."
      if [ "\$count" -eq 2 ]; then
        touch ${key_reads} && touch ${key_reports}
      else
        echo "Some of the required keys are missing in the cache."
        exit 1
      fi
    fi

    if grep -q "All samples are empty after processing with fastp" output.txt || grep -q "All samples are empty after processing with fastp" error.txt; then
      echo "All reads were removed from this sample - the output was empty."
      exit 125
    elif grep -q "xxx_00" output.txt || grep -q "xxx_00" error.txt; then
      echo "Empty XXX samples found in the data."
      exit 126
    elif grep -q "Already unlocked" output.txt || grep -q "Already unlocked" error.txt; then
      echo "Already unlocked error - please investigate the full log."

      count=\$(ls ${q2cacheDir}/keys/ | grep -E '${key_reads}|${key_reports}' | wc -l)
      echo "File count is: \$count."
      if [ "\$count" -eq 2 ]; then
        touch ${key_reads} && touch ${key_reports}
      else
        echo "Some of the required keys are missing in the cache."
        exit 1
      fi

      echo "This error will be ignored since all the required keys are present in the cache."
      qiime_exit_code=0
    fi

    exit \$qiime_exit_code
    """
}

process VISUALIZE_FASTP {
    cpus 1
    memory { 4.GB * task.attempt }
    maxRetries 3
    errorStrategy 'retry'
    time { 2.h * task.attempt }
    publishDir params.publishDir, mode: 'copy'
    scratch true

    input:
    path fastp_reports
    path q2_cache

    output:
    path "${params.runId}-reads-qc-fastp.qzv"

    script:
    """
    qiime fastp visualize \
      --verbose \
      --i-reports ${params.q2cacheDir}:${fastp_reports} \
      --o-visualization ${params.runId}-reads-qc-fastp.qzv
    """
}

process REMOVE_HOST {
    label "hostRemoval"
    label "needsInternet"
    errorStrategy { task.exitStatus == 137 ? 'retry' : 'terminate' } 
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(reads)
    path q2_cache

    output:
    tuple val(sample_id), path(key), emit: reads
    path "human_reference_index", emit: reference, optional: true

    script:
    index_flag = params.host_removal.database.key ? "--i-index ${params.host_removal.database.cache}:${params.host_removal.database.key}" : ""
    key = "${params.runId}_reads_no_host_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}

    if [ -f ${params.host_removal.database.cache}/keys/${params.host_removal.database.key} ]; then
      echo Database ${params.host_removal.database.key} already exists in the cache ${params.host_removal.database.cache} and will be used for filtering
      qiime quality-control filter-reads \
        --verbose \
        --i-demultiplexed-sequences ${params.q2cacheDir}:${reads} \
        --i-database ${params.host_removal.database.cache}:${params.host_removal.database.key} \
        --p-n-threads ${task.cpus} \
        --p-mode ${params.host_removal.mode} \
        --p-sensitivity ${params.host_removal.sensitivity} \
        --p-ref-gap-open-penalty ${params.host_removal.ref_gap_open_penalty} \
        --p-ref-gap-ext-penalty ${params.host_removal.ref_gap_ext_penalty} \
        --o-filtered-sequences ${params.q2cacheDir}:${key}
    elif [[ "${params.host_removal.human}" == "true" ]]; then
      echo Database ${params.host_removal.database.key} does not exist in the cache ${params.host_removal.database.cache} and will be constructed by the "filter-reads-pangenome" action
      qiime annotate filter-reads-pangenome \
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
      && touch human_reference_index
    else
      echo Database ${params.host_removal.database.key} does not exist in the cache ${params.host_removal.database.cache} - please provide a key to an exisitng database or toggle the "human" option to "true"
      exit 1
    fi
    
    touch ${key}
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
    storeDir params.storeDir
    scratch true
    time { 2.h * task.attempt }
    maxRetries 3

    input:
    path cache_key
    val prefix
    val qiime_action
    val qiime_input_flag
    val qiime_output_flag
    val isInputReads

    output:
    path "${prefix}*"

    script:
    if (isInputReads) {
      inputCachePath = params.inputReadsCache
    } else {
      inputCachePath = params.q2cacheDir
    }
    """
    if [ ! -f "${params.q2cacheDir}/keys/${prefix}collection" ]; then
      qiime ${qiime_action} \
      ${qiime_input_flag} ${inputCachePath}:${cache_key} \
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
    label "collation"
    cpus 1
    scratch true
    time { 2.h * task.attempt }
    maxRetries 3

    input:
    val id_and_paths
    val cache_key_out 
    val qiime_action
    val qiime_input_flag
    val qiime_output_flag
    val clean_up

    output:
    path "${cache_key_out}"

    script:
    def inputString = id_and_paths.collect { item ->
        def sample_id = item[0]
        def path = item[1]
        def key = new File(path.toString()).getName()
        "${params.q2TemporaryCachesDir}/${sample_id}:${key}"
    }.join(' ')
  
    """
    echo "Combined input: ${inputString}"
    
    qiime ${qiime_action} \\
      ${qiime_input_flag} ${inputString} \\
      ${qiime_output_flag} ${params.q2cacheDir}:${cache_key_out} \\
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
    scratch true
    tag "${sample_id}"
    time { 2.h * task.attempt }
    maxRetries 3
    
    input:
    tuple val(sample_id), path(reads)
    path q2_cache

    output:
    tuple val(sample_id), path(key)

    script:
    key = "${params.runId}_reads_counts_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime demux tabulate-read-counts \
      --verbose \
      --i-sequences ${params.q2cacheDir}:${reads} \
      --o-counts ${params.q2cacheDir}:${key} \
      && touch ${key}
    """
}

process FILTER_SAMPLES {
    errorStrategy { task.exitStatus == 125 ? 'ignore' : 'retry' }
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    time { 2.h * task.attempt }
    maxRetries 3
    
    input:
    tuple val(sample_id), path(reads), path(metadata)
    val query
    path q2_cache

    output:
    tuple val(sample_id), path(key)

    script:
    key = "${params.runId}_reads_filtered_${sample_id}"
    """
    echo Processing sample ${sample_id}

    set +e
    qiime demux filter-samples \
      --verbose \
      --i-demux ${params.q2cacheDir}:${reads} \
      --m-metadata-file ${params.q2cacheDir}:${metadata} \
      --p-where ${query} \
      --o-filtered-demux ${params.q2cacheDir}:${key} > output.txt 2> error.txt
    
    qiime_exit_code=\$?
    echo "QIIME exit code: \$qiime_exit_code"
    set -e

    cat output.txt >> .command.out
    cat error.txt >> .command.err

    if [ \$qiime_exit_code -eq 0 ]; then
      count=\$(ls ${params.q2cacheDir}/keys/ | grep ${key} | wc -l)
      if [ "\$count" -eq 0 ]; then
        echo "Some of the required keys are missing in the cache."
        exit 1
      else
        touch ${key}
      fi
    fi

    if grep -q "No filtering requested" output.txt || grep -q "No filtering requested" error.txt; then
      echo "The generated artifact did not contain any samples."
      exit 125
    elif grep -q "Already unlocked" output.txt || grep -q "Already unlocked" error.txt; then
      echo "Already unlocked error - please investigate the full log."

      count=\$(ls ${params.q2cacheDir}/keys/ | grep ${key} | wc -l)
      if [ "\$count" -eq 0 ]; then
        echo "Some of the required keys are missing in the cache."
        exit 1
      else
        touch ${key}
      fi

      echo "This error will be ignored since all the required keys are present in the cache."
      qiime_exit_code=0
    fi

    exit \$qiime_exit_code
    """
}
