process FETCH_GENOMES {
    label "needsInternet"
    publishDir params.publishDir

    output:
    path params.read_simulation.sampleGenomes

    script:
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
    scratch true
    tag "${sample_id}"
    errorStrategy 'retry'
    maxRetries 3

    input:
    tuple val(sample_id), path(genomes)

    output:
    tuple val(sample_id), path(reads), emit: reads
    tuple val(sample_id), path(output_genomes), emit: genomes
    tuple val(sample_id), path(abundances), emit: abundances

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    reads = "${params.runId}_reads_${sample_id}"
    output_genomes = "${params.runId}_output_genomes_${sample_id}"
    abundances = "${params.runId}_output_abundances_${sample_id}"
    """
    if [ ! -d "${q2cacheDir}" ]; then
      qiime tools cache-create --cache ${q2cacheDir}
    fi

    qiime assembly generate-reads \
      --verbose \
      --i-genomes ${genomes} \
      --p-sample-names ${sample_id} \
      --p-cpus ${task.cpus} \
      --p-n-genomes ${params.read_simulation.nGenomes} \
      --p-n-reads ${params.read_simulation.readCount} \
      --p-seed ${params.read_simulation.seed} \
      --p-abundance ${params.read_simulation.abundance} \
      --p-gc-bias ${params.read_simulation.gc_bias} \
      --o-reads ${q2cacheDir}:${reads} \
      --o-template-genomes ${q2cacheDir}:${output_genomes} \
      --o-abundances ${q2cacheDir}:${abundances} \
    && touch ${reads} \
    && touch ${output_genomes} \
    && touch ${abundances}
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
    if [ ! -d "${q2cacheDir}" ]; then
      echo "Creating cache for ${_id}..."
      qiime tools cache-create --cache ${q2cacheDir}
    else
      echo "Cache already exists for ${_id}"
    fi

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
      --p-threads ${task.cpus} \
      --o-single-reads ${q2cacheDir}:${reads_single} \
      --o-paired-reads ${q2cacheDir}:${reads_paired} \
      --o-failed-runs ${q2cacheDir}:${failed_runs} > output.txt 2> error.txt

    qiime_exit_code=\$?
    echo "QIIME exit code: \$qiime_exit_code"
    set -e
    
    cat output.txt >> .command.out
    cat error.txt >> .command.err

    if grep -q "Neither single- nor paired-end sequences could be downloaded" output.txt || grep -q "Neither single- nor paired-end sequences could be downloaded" error.txt; then
      echo "Neither single- nor paired-end sequences could be downloaded."
      touch ${reads_paired} && touch ${reads_single} && touch ${failed_runs}
      exit 125
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
      touch ${reads_paired} && touch ${reads_single} && touch ${failed_runs}
      exit 125
    else
      echo "No empty samples found for key \$key"
    fi

    touch ${reads_paired} && touch ${reads_single} && touch ${failed_runs}

    exit \$qiime_exit_code
    """
}

process SUBSAMPLE_READS {
    label "readSubsampling"
    storeDir params.storeDir
    cpus 1
    scratch true
    tag "${sample_id}"

    input:
    tuple val(sample_id), path(reads)

    output:
    tuple val(sample_id), path(reads_subsampled)

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    reads_subsampled = "${params.runId}_reads_subsampled_${params.read_subsampling.fraction.toString().replace(".", "_")}_${sample_id}"
    if (params.read_subsampling.paired) {
      """
      echo Processing sample ${sample_id}
      qiime demux subsample-paired \
        --verbose \
        --i-sequences ${q2cacheDir}:${reads} \
        --p-fraction ${params.read_subsampling.fraction} \
        --o-subsampled-sequences ${q2cacheDir}:${reads_subsampled} \
      && touch ${reads_subsampled}
      """
    } else {
      """
      echo Processing sample ${sample_id}
      qiime demux subsample-single \
        --verbose \
        --i-sequences ${q2cacheDir}:${reads} \
        --p-fraction ${params.read_subsampling.fraction} \
        --o-subsampled-sequences ${q2cacheDir}:${reads_subsampled} \
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

    if grep -q "All samples are empty after processing with fastp" output.txt || grep -q "All samples are empty after processing with fastp" error.txt; then
      echo "All reads were removed from this sample - the output was empty."
      touch ${key_reads} && touch ${key_reports}
      exit 125
    elif grep -q "xxx_00" output.txt || grep -q "xxx_00" error.txt; then
      echo "Empty XXX samples found in the data."
      touch ${key_reads} && touch ${key_reports}
      exit 126
    fi

    touch ${key_reads} && touch ${key_reports}

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
    errorStrategy 'retry'
    maxRetries 3
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    
    input:
    tuple val(sample_id), path(reads)

    output:
    tuple val(sample_id), path(key), emit: reads
    path "human_reference_index", emit: reference, optional: true

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    index_flag = params.databases.hostRemoval.key ? "--i-index ${params.databases.hostRemoval.cache}:${params.databases.hostRemoval.key}" : ""
    key = "${params.runId}_reads_no_host_partitioned_${sample_id}"
    """
    echo Processing sample ${sample_id}

    if [ -f ${params.databases.hostRemoval.cache}/keys/${params.databases.hostRemoval.key} ]; then
      echo Database ${params.databases.hostRemoval.key} already exists in the cache ${params.databases.hostRemoval.cache} and will be used for filtering
      qiime quality-control filter-reads \
        --verbose \
        --i-demultiplexed-sequences ${q2cacheDir}:${reads} \
        --i-database ${params.databases.hostRemoval.cache}:${params.databases.hostRemoval.key} \
        --p-n-threads ${task.cpus} \
        --p-mode ${params.host_removal.mode} \
        --p-sensitivity ${params.host_removal.sensitivity} \
        --p-ref-gap-open-penalty ${params.host_removal.ref_gap_open_penalty} \
        --p-ref-gap-ext-penalty ${params.host_removal.ref_gap_ext_penalty} \
        --o-filtered-sequences ${q2cacheDir}:${key}
    elif [[ "${params.host_removal.human}" == "true" ]]; then
      echo Database ${params.databases.hostRemoval.key} does not exist in the cache ${params.databases.hostRemoval.cache} and will be constructed by the "filter-reads-pangenome" action
      qiime annotate filter-reads-pangenome \
        --verbose \
        --i-reads ${q2cacheDir}:${reads} \
        --p-n-threads ${task.cpus} \
        --p-mode ${params.host_removal.mode} \
        --p-sensitivity ${params.host_removal.sensitivity} \
        --p-ref-gap-open-penalty ${params.host_removal.ref_gap_open_penalty} \
        --p-ref-gap-ext-penalty ${params.host_removal.ref_gap_ext_penalty} \
        --o-filtered-reads ${q2cacheDir}:${key} \
        ${index_flag} \
        --o-reference-index ${params.databases.hostRemoval.cache}:human_reference_index > output.log 2>&1 \
      && touch human_reference_index
    else
      echo Database ${params.databases.hostRemoval.key} does not exist in the cache ${params.databases.hostRemoval.cache} - please provide a key to an exisitng database or toggle the "human" option to "true"
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
    memory { 2.GB * task.attempt }
    time { 2.h * task.attempt }

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

process IMPORT_READS {
    tag "${_id}"
    scratch true
    errorStrategy 'retry'
    maxRetries 3
    memory { 2.GB * task.attempt }
    time { 2.h * task.attempt }

    input:
    tuple val(_id), path(reads_fwd), path(reads_rev)

    output:
    tuple val(_id), path(key)

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${_id}"
    key = "${params.runId}_reads_${_id}"
    """
    echo "Creating cache for ${_id}..."
    if [ ! -d "${q2cacheDir}" ]; then
      qiime tools cache-create --cache ${q2cacheDir}
    fi

    echo "Creating manifest file..."
    if [ -n "${reads_rev}" ]; then
        echo -e "sample-id\tforward-absolute-filepath\treverse-absolute-filepath" > manifest.tsv
        echo -e "${_id}\t\$(readlink -f ${reads_fwd})\t\$(readlink -f ${reads_rev})" >> manifest.tsv
        semanticType="PairedEndSequencesWithQuality"
        dataFormat="PairedEndFastqManifestPhred33V2"
    else
        echo -e "sample-id\tforward-absolute-filepath" > manifest.tsv
        echo -e "${_id}\t\$(readlink -f ${reads_fwd})" >> manifest.tsv
        semanticType="SequencesWithQuality"
        dataFormat="SingleEndFastqManifestPhred33V2"
    fi
    
    echo "Importing reads..."
    qiime tools cache-import \
      --cache ${q2cacheDir} \
      --key ${key} \
      --type "SampleData[\$semanticType]" \
      --input-path manifest.tsv \
      --input-format \$dataFormat
    
    touch ${key}
    """
}

process PARTITION_DEREP_MAGS {
    cpus 1
    storeDir params.storeDir
    time { 2.h * task.attempt }
    memory { 2.GB * task.attempt }
    maxRetries 3
    errorStrategy 'retry'

    input:
    path mags_derep
    path q2_cache

    output:
    path "${params.runId}_mags_derep_partitioned_*"

    script:
    """
    uuid=\$(cat ${params.q2cacheDir}/keys/${mags_derep} | grep 'data' | awk '{print \$2}')
    mags=\$(ls ${params.q2cacheDir}/data/\$uuid/data/*.{fa,fasta} 2>/dev/null | xargs -n 1 basename | sed -E 's/\\.(fa|fasta)\$//')
    mkdir -p "${params.q2TemporaryCachesDir}/mags"

    for mag in \${mags}; do
      q2cacheDir="${params.q2TemporaryCachesDir}/mags/\$mag"
      key="${params.runId}_mags_derep_partitioned_\$mag"
      if [ ! -d \$q2cacheDir ]; then
        echo "Creating cache \$q2cacheDir..."
        qiime tools cache-create --cache \$q2cacheDir
      fi

      echo "id" > metadata.tsv
      echo "\$mag" >> metadata.tsv

      echo "Filtering \$mag..."
      cat metadata.tsv

      qiime annotate filter-derep-mags \
        --verbose \
        --i-mags ${params.q2cacheDir}:${mags_derep} \
        --m-metadata-file metadata.tsv \
        --o-filtered-mags \$q2cacheDir:\$key
      
      touch \$key
    done
    """  
}

process COLLATE_PARTITIONS {
    label "collation"
    cpus 1
    scratch true
    time { 2.h * task.attempt }
    memory { 2.GB * task.attempt }
    errorStrategy 'retry'
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

process COLLATE_PARTITIONS_DEREP {
    label "collation"
    cpus 1
    scratch true
    time { 2.h * task.attempt }
    memory { 2.GB * task.attempt }
    maxRetries 3
    errorStrategy 'retry'

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
        "${params.q2TemporaryCachesDir}/mags/${sample_id}:${key}"
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
    memory { 2.GB * task.attempt }
    maxRetries 3
    errorStrategy 'retry'
    
    input:
    tuple val(sample_id), path(reads)

    output:
    tuple val(sample_id), path(key)

    script:
    q2cacheDir = "${params.q2TemporaryCachesDir}/${sample_id}"
    key = "${params.runId}_reads_counts_${sample_id}"
    """
    echo Processing sample ${sample_id}
    qiime demux tabulate-read-counts \
      --verbose \
      --i-sequences ${q2cacheDir}:${reads} \
      --o-counts ${q2cacheDir}:${key} \
      && touch ${key}
    """
}

process FILTER_SAMPLES {
    errorStrategy { task.exitStatus == 125 ? 'ignore' : 'retry' }
    storeDir params.storeDir
    scratch true
    tag "${sample_id}"
    time { 2.h * task.attempt }
    memory { 2.GB * task.attempt }
    maxRetries 3
    
    input:
    tuple val(sample_id), path(reads), path(metadata)
    val query
    val should_partition

    output:
    tuple val(sample_id), path(key)

    script:
    if (should_partition) {
      q2cacheDirIn = params.inputReadsCache
      q2cacheDirOut = "${params.q2TemporaryCachesDir}/${sample_id}"
      key = "${params.runId}_reads_partitioned_${sample_id}"
    } else {
      q2cacheDirIn = "${params.q2TemporaryCachesDir}/${sample_id}"
      q2cacheDirOut = "${params.q2TemporaryCachesDir}/${sample_id}"
      key = "${params.runId}_reads_filtered_${sample_id}"
    }
    if (should_partition) {
      """
      echo Creating partition for sample ${sample_id}

      echo "id" > _metadata.tsv
      echo "${sample_id}" >> _metadata.tsv

      if [ ! -d "${q2cacheDirOut}" ]; then
        qiime tools cache-create --cache ${q2cacheDirOut}
      fi

      qiime demux filter-samples \
        --verbose \
        --i-demux ${q2cacheDirIn}:${reads} \
        --m-metadata-file _metadata.tsv \
        --o-filtered-demux ${q2cacheDirOut}:${key}

      touch ${key}
      """
    } else {
      """
      echo Processing sample ${sample_id}

      set +e
      qiime demux filter-samples \
        --verbose \
        --i-demux ${q2cacheDirIn}:${reads} \
        --m-metadata-file ${q2cacheDirIn}:${metadata} \
        --p-where ${query} \
        --o-filtered-demux ${q2cacheDirOut}:${key} > output.txt 2> error.txt
      
      qiime_exit_code=\$?
      echo "QIIME exit code: \$qiime_exit_code"
      set -e

      cat output.txt >> .command.out
      cat error.txt >> .command.err

      if grep -q "No filtering requested" output.txt || grep -q "No filtering requested" error.txt; then
        echo "The generated artifact did not contain any samples."
        exit 125
      fi

      touch ${key}

      exit \$qiime_exit_code
      """
    }
}
