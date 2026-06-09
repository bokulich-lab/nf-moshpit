#!/usr/bin/env nextflow

include { INIT_CACHE } from './modules/data_prep'
include { IMPORT_READS } from './modules/data_prep'
include { FETCH_SEQS } from './modules/data_prep'
include { FETCH_GENOMES } from './modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_CONTIGS } from './modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS } from './modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS_DEREP } from './modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS_DEREP_FT } from './modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS_FILTERED } from './modules/data_prep'
include { FETCH_ARTIFACT as FETCH_MULTIPLIED_TABLE } from './modules/data_prep'
include { SIMULATE_READS } from './modules/data_prep'
include { SIMULATE_READS_MASON } from './modules/data_prep'
include { SUBSAMPLE_READS } from './modules/data_prep'
include { REMOVE_HOST } from './modules/data_prep'
include { PROCESS_READS_FASTP } from './modules/data_prep'
include { VISUALIZE_FASTP } from './modules/data_prep'
include { MAKE_REPORT } from './modules/data_prep'
include { PARTITION_DEREP_MAGS } from './modules/data_prep'
include { COLLATE_PARTITIONS } from './modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_FASTP_REPORTS } from './modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_READS } from './modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_FT } from './modules/data_prep'
include { TABULATE_READ_COUNTS } from './modules/data_prep'
include { FILTER_SAMPLES } from './modules/data_prep'
include { FILTER_SAMPLES as PARTITION_READS } from './modules/data_prep'
include { ARCHIVE_SAMPLE_CACHE } from './modules/data_prep'
include { REMOVE_FROM_CACHE as CLEANUP_INPUT } from './modules/data_prep'
include { REMOVE_FROM_CACHE as CLEANUP_SUBSAMPLED } from './modules/data_prep'
include { REMOVE_FROM_CACHE as CLEANUP_FASTP } from './modules/data_prep'
include { REMOVE_FROM_CACHE as CLEANUP_HOST } from './modules/data_prep'
include { REMOVE_FROM_CACHE as CLEANUP_FILTERED } from './modules/data_prep'
include { FIX_CACHE_PERMISSIONS } from './modules/data_prep'
include { FIX_CACHE_PERMISSIONS as FIX_CACHE_PERMISSIONS_MAIN } from './modules/data_prep'
include { ASSEMBLE } from './subworkflows/assembly'
include { BIN } from './subworkflows/binning'
include { BIN_NO_BUSCO } from './subworkflows/binning'
include { DEREPLICATE } from './subworkflows/dereplication'
include { CLASSIFY_READS } from './subworkflows/classification'
include { CLASSIFY_CONTIGS } from './subworkflows/classification'
include { CLASSIFY_MAGS } from './subworkflows/classification'
include { CLASSIFY_MAGS_DEREP } from './subworkflows/classification'
include { COLLAPSE_CONTIGS } from './modules/taxonomic_classification'
include { ANNOTATE_EGGNOG_MAGS_DEREP } from './subworkflows/functional_annotation'
include { ANNOTATE_EGGNOG_MAGS } from './subworkflows/functional_annotation'
include { ANNOTATE_EGGNOG_CONTIGS } from './subworkflows/functional_annotation'
include { MAG_ABUNDANCE } from './subworkflows/abundance_estimation'
include { FETCH_DIAMOND_DB } from './modules/functional_annotation'
include { FETCH_EGGNOG_DB } from './modules/functional_annotation'
include { FETCH_KRAKEN2_DB } from './modules/taxonomic_classification'
include { MULTIPLY_TABLES } from './modules/functional_annotation'
include { FETCH_KAIJU_DB } from './modules/taxonomic_classification'
include { CLASSIFY_READS_KAIJU } from './subworkflows/classification'
include { CLASSIFY_CONTIGS_KAIJU } from './subworkflows/classification'

include { validateParameters } from './modules/validation.nf'
include { getDirectorySizeInGB } from './modules/utils.nf'

nextflow.enable.dsl = 2

validateParameters()

def executionStats = [:]
def trackMetric = { key, value ->
    executionStats[key] = value
}
def writeLog = { value ->
    log.info value
}

workflow {
    def directoryPaths = [
        "${params.storeDir}",
        "${params.publishDir}",
        "${params.traceDir}",
        "${params.containerCacheDir}",
        "${params.q2TemporaryCachesDir}",
        "${params.archiveDir}"
    ]
    directoryPaths.each { d ->
        def dir = new File(d)
        if (!dir.exists()) {
            dir.mkdirs()
        }
    }

    cache = INIT_CACHE()
    qzv_reports = Channel.empty()
    workflow_barrier = Channel.empty()

    // Log header with workflow version and timestamp
    writeLog("======== MOSHPIT WORKFLOW REPORT =========")
    writeLog("Run ID: ${params.runId}")
    writeLog("Start time: " + new Date().format('yyyy-MM-dd HH:mm:ss'))
    writeLog("==========================================")
    writeLog("\n============ CONFIGURATION ==============")
    writeLog("Output directory: ${params.outputDir}")
    if (params.condaEnv) {
        writeLog("Using conda environment: ${params.condaEnv}")
    }
    if (params.container) {
        writeLog("Using container: ${params.container}")
    }
    writeLog("==========================================\n")
    
    // prepare input reads
    if (params.inputReadsManifest) {
        ids = Channel
            .fromPath(params.inputReadsManifest)
            .splitCsv(header: true, sep: ',')
            .map { row -> tuple(row.id, row.forward, row.reverse) }

        writeLog("Reading reads from manifest: ${params.inputReadsManifest}")
        reads = IMPORT_READS(ids)
        reads | count | subscribe { trackMetric("Samples imported from manifest", it) }
    } else if (params.inputReads && params.inputReadsCache && params.metadata) {
        reads = Channel.fromPath(params.inputReads)
        metadata = Channel.fromPath(params.metadata)
        reads_with_ids = Channel
            .fromPath(params.metadata)
            .splitCsv(header: true, sep: '\t')
            .map { row -> row.id }
            .combine(reads)
            .combine(metadata)

        writeLog("Using existing reads '${params.inputReads}' from ${params.inputReadsCache} cache")
        reads = PARTITION_READS(reads_with_ids, "", true)
        reads | count | subscribe { trackMetric("Samples partitioned from an input artifact", it) }
    } else if (params.fondueAccessionIds) {
        ids = Channel
            .fromPath(params.fondueAccessionIds)
            .splitCsv(header: true, sep: '\t')
            .map { row -> row.id }
        
        writeLog("Reading SRA accessions from: ${params.fondueAccessionIds}")
        ids | count | subscribe { trackMetric("SRA accessions to fetch", it) }
        
        fetched_reads = FETCH_SEQS(ids)
        reads = (params.fondue.paired) ? fetched_reads.paired : fetched_reads.single
        reads | count | subscribe { trackMetric("Samples returned from fondue", it) }
    } else if (params.read_simulation.samples) {
        writeLog("Simulating samples from: ${params.read_simulation.samples}")
        simulation_data = Channel
            .fromPath(params.read_simulation.samples)
            .splitCsv(header: true, sep: ',')
            .map { row -> tuple(row.id, row.profile, row.readCount, row.readLength, row.genomesPath) }

        simulated_reads = SIMULATE_READS_MASON(simulation_data)

        simulated_tables = SIMULATE_READS_MASON.out.reads.map { _id, reads, table -> [_id, table] } | collect(flat: false)
        simulated_tables = COLLATE_FT(simulated_tables, "${params.runId}_mason_ft", "feature-table merge", "--i-tables", "--o-merged-table", true)

        reads = simulated_reads.reads | map { _id, reads, table -> [_id, reads] }
        reads | count | subscribe { trackMetric("Samples simulated", it) }
    } else {
        writeLog("Simulating reads from fetched genomes")
        writeLog("Number of random genomes to fetch: ${params.read_simulation.nGenomes}")
        writeLog("Number of samples to simulate: ${params.read_simulation.sampleNames.split(',').size()}")
        writeLog("Reads per sample: ${params.read_simulation.readCount}")
        
        genomes = FETCH_GENOMES()
        ids = Channel.of(params.read_simulation.sampleNames.split(','))
        ids_with_genomes = ids.combine(genomes)
        simulated_reads = SIMULATE_READS(ids_with_genomes)
        reads = simulated_reads.reads
        reads | count | subscribe { trackMetric("Samples simulated", it) }
    }

    reads_partitioned = reads

    // subsample reads
    if (params.read_subsampling.enabled) {
        input_reads = reads_partitioned
        reads_partitioned = SUBSAMPLE_READS(reads_partitioned)
        reads_partitioned | count | subscribe { trackMetric("Samples after subsampling", it) }
        
        if (!params.retain.input) {
            CLEANUP_INPUT(input_reads.join(reads_partitioned).map { id, i, o -> tuple(id, i) })
        }
    }

    // perform read QC and trimming
    input_reads_fastp = reads_partitioned
    fastp_results = PROCESS_READS_FASTP(reads_partitioned)
    reads_partitioned = fastp_results | map { _id, reads, report -> [_id, reads] }
    
    if ((params.read_subsampling.enabled && !params.retain.subsampling) || (!params.read_subsampling.enabled && !params.retain.input)) {
        if (params.read_subsampling.enabled) {
            CLEANUP_SUBSAMPLED(input_reads_fastp.join(fastp_results).map { id, i, o, r -> tuple(id, i) })
        } else {
            CLEANUP_INPUT(input_reads_fastp.join(fastp_results).map { id, i, o, r -> tuple(id, i) })
        }
    }
    reads_partitioned | count | subscribe { trackMetric("Samples after fastp processing", it) }
    fastp_reports = fastp_results | map { _id, reads, report -> tuple(_id, report) } | collect(flat: false)
    fastp_reports_all = COLLATE_FASTP_REPORTS(fastp_reports, "${params.runId}_fastp_reports", "fastp collate-fastp-reports", "--i-reports", "--o-collated-reports", true)
    VISUALIZE_FASTP(fastp_reports_all, cache)

    qzv_reports = qzv_reports.mix(VISUALIZE_FASTP.out.qzv)
    workflow_barrier = workflow_barrier.mix(VISUALIZE_FASTP.out.qzv)
    deepest_signal = VISUALIZE_FASTP.out

    // remove host reads
    if (params.host_removal.enabled) {
        input_reads_host = reads_partitioned
        filtering_results = REMOVE_HOST(reads_partitioned)
        reads_partitioned = filtering_results.reads
        reads_partitioned | count | subscribe { trackMetric("Samples after host removal", it) }

        if (!params.retain.fastp) {
            CLEANUP_FASTP(input_reads_host.join(filtering_results.reads).map { id, i, o -> tuple(id, i) })
        }
    }

    if (params.taxonomic_classification.enabledFor != "") {
        FETCH_KRAKEN2_DB()

        def dirInfo = getDirectorySizeInGB("${params.databases.kraken2.cache}/keys/${params.databases.kraken2.key}", "${params.databases.kraken2.cache}/data")
        params.taxonomic_classification = params.taxonomic_classification ?: [:]
        params.taxonomic_classification.kraken2 = params.taxonomic_classification.kraken2 ?: [:]
        params.taxonomic_classification.kraken2.memory = dirInfo.sizeInGBRoundedUp
    }

    if (params.taxonomic_classification.kaiju.enabledFor != "") {
        FETCH_KAIJU_DB()
        
        FETCH_KAIJU_DB.out.kaiju_db
            .subscribe {
                try {
                    def dirInfo = getDirectorySizeInGB("${params.databases.kaiju.cache}/keys/${params.databases.kaiju.key}", "${params.databases.kaiju.cache}/data")
                    params.taxonomic_classification = params.taxonomic_classification ?: [:]
                    params.taxonomic_classification.kaiju = params.taxonomic_classification.kaiju ?: [:]
                    params.taxonomic_classification.kaiju.memory = dirInfo.sizeInGBRoundedUp
                } catch (Exception e) {
                    log.warn "Unable to auto-size Kaiju memory from cache key `${params.databases.kaiju.key}`. Keeping configured value. Cause: ${e.message}"
                }
            }
    }

    if (params.functional_annotation.enabledFor != "") {
        params.functional_annotation = params.functional_annotation ?: [:]
        params.functional_annotation.ortholog_search = params.functional_annotation.ortholog_search ?: [:]
        params.functional_annotation.annotation = params.functional_annotation.annotation ?: [:]

        if (params.functional_annotation.ortholog_search.dbInMemory) {
            def orthologDBInfo = getDirectorySizeInGB("${params.databases.eggnogOrthologs.cache}/keys/${params.databases.eggnogOrthologs.key}", "${params.databases.eggnogOrthologs.cache}/data")
            params.functional_annotation.ortholog_search.memory = orthologDBInfo.sizeInGBRoundedUp
        } else {
            params.functional_annotation.ortholog_search.memory = 2
        }

        if (params.functional_annotation.annotation.dbInMemory) {
            def annotationDBInfo = getDirectorySizeInGB("${params.databases.eggnogAnnotations.cache}/keys/${params.databases.eggnogAnnotations.key}", "${params.databases.eggnogAnnotations.cache}/data")
            params.functional_annotation.annotation.memory = annotationDBInfo.sizeInGBRoundedUp
        } else {
            params.functional_annotation.annotation.memory = 2
        }
        
    }
    // remove samples with low read counts
    if (params.sample_filtering.enabled) {
        input_reads_filter = reads_partitioned
        read_counts = TABULATE_READ_COUNTS(reads_partitioned)
        reads_with_counts = reads_partitioned.combine(read_counts, by: 0)
        reads_partitioned = FILTER_SAMPLES(reads_with_counts, "'\"Demultiplexed sequence count\">${params.sample_filtering.minReads}'", false)
        reads_partitioned | count | subscribe { trackMetric("Samples after filtering by read count", it) }
        
        if ((params.host_removal.enabled && !params.retain.host_removal) || (!params.host_removal.enabled && !params.retain.fastp)) {
             if (params.host_removal.enabled) {
                CLEANUP_HOST(input_reads_filter.join(reads_partitioned).map { id, i, o -> tuple(id, i) })
             } else {
                CLEANUP_FASTP(input_reads_filter.join(reads_partitioned).map { id, i, o -> tuple(id, i) })
             }
        }
    }

    // classify reads
    if (params.taxonomic_classification.enabledFor.contains("reads")) {
        reads_classification = CLASSIFY_READS(reads_partitioned, FETCH_KRAKEN2_DB.out.kraken2_db, FETCH_KRAKEN2_DB.out.bracken_db, cache)
        qzv_reports = qzv_reports.mix(reads_classification.qzv)
        workflow_barrier = workflow_barrier.mix(reads_classification.qzv)
    }

    if (params.taxonomic_classification.kaiju.enabledFor.contains("reads")) {
        reads_kaiju_classification = CLASSIFY_READS_KAIJU(reads_partitioned, FETCH_KAIJU_DB.out.kaiju_db, cache)
        qzv_reports = qzv_reports.mix(reads_kaiju_classification.qzv)
        workflow_barrier = workflow_barrier.mix(reads_kaiju_classification.qzv)
    }

    // assemble and evaluate
    if (params.genome_assembly.enabled) {
        contigs = ASSEMBLE(reads_partitioned, cache)
        qzv_reports = qzv_reports.mix(contigs.qzv)
        workflow_barrier = workflow_barrier.mix(contigs.qzv)

        contigs.contigs | count | subscribe { trackMetric("Samples after contig assembly and filtering", it) }

        if (params.functional_annotation.enabledFor != "") {
            diamond_db = FETCH_DIAMOND_DB()
            eggnog_db = FETCH_EGGNOG_DB()
        }

        // classify contigs
        if (params.taxonomic_classification.enabledFor.contains("contigs")) {
            classification = CLASSIFY_CONTIGS(contigs.contigs, FETCH_KRAKEN2_DB.out.kraken2_db, cache)

            workflow_barrier = workflow_barrier.mix(classification.taxonomy)

            if (params.abundance_estimation.enabledFor.contains("contigs")) {
                    contigs_collapsed = COLLAPSE_CONTIGS(classification.feature_map, classification.taxonomy, contigs.contig_abundance)
                    qzv_reports = qzv_reports.mix(contigs_collapsed.qzv)
                    workflow_barrier = workflow_barrier.mix(contigs_collapsed.qzv)
            }
        }
        if (params.taxonomic_classification.kaiju.enabledFor.contains("contigs")) {
            CLASSIFY_CONTIGS_KAIJU(contigs.contigs, FETCH_KAIJU_DB.out.kaiju_db, cache)
            workflow_barrier = workflow_barrier.mix(CLASSIFY_CONTIGS_KAIJU.out.kaiju_classification)
        }

        // annotate contigs
        if (params.functional_annotation.enabledFor.contains("contigs")) {
            annotation_signal = ANNOTATE_EGGNOG_CONTIGS(contigs.contigs, diamond_db, eggnog_db, cache)
            workflow_barrier = workflow_barrier.mix(annotation_signal)
        }

        // bin contigs into MAGs and evaluate
        if (params.binning.enabled) {
            if (params.binning.qc.busco.enabled) {
                binning_results = BIN(contigs.contigs, contigs.mapped_reads, cache)
            } else {
                binning_results = BIN_NO_BUSCO(contigs.contigs, contigs.mapped_reads, cache)
            }
                qzv_reports = qzv_reports.mix(binning_results.qzv)
            
            binning_results.bins | count | subscribe { trackMetric("Samples after binning", it) }
            deepest_signal = binning_results.bins_collated
            workflow_barrier = workflow_barrier.mix(binning_results.bins_collated)
            
            // classify MAGs
            if (params.taxonomic_classification.enabledFor.contains("mags")) {
                CLASSIFY_MAGS(binning_results.bins, FETCH_KRAKEN2_DB.out.kraken2_db, cache)
                workflow_barrier = workflow_barrier.mix(CLASSIFY_MAGS.out.taxonomy)
            }

            // annotate MAGs
            if (params.functional_annotation.enabledFor.contains("mags")) {
                annotation_signal_mags = ANNOTATE_EGGNOG_MAGS(binning_results.bins, diamond_db, eggnog_db)
                workflow_barrier = workflow_barrier.mix(annotation_signal_mags)
            }


            if (params.dereplication.enabled) {
                DEREPLICATE(binning_results.bins_collated, cache)
                deepest_signal = DEREPLICATE.out.bins_derep
                workflow_barrier = workflow_barrier.mix(DEREPLICATE.out.bins_derep)
                
                // estimate abundance
                if (params.abundance_estimation.enabledFor.contains("derep")) {
                    MAG_ABUNDANCE(DEREPLICATE.out.bins_derep, reads_partitioned, cache)
                    deepest_signal = MAG_ABUNDANCE.out.feature_table
                    workflow_barrier = workflow_barrier.mix(MAG_ABUNDANCE.out.feature_table)
                }

                if (params.taxonomic_classification.enabledFor.contains("derep") || params.functional_annotation.enabledFor.contains("derep")) {
                    // classify dereplicated MAGs
                    if (params.taxonomic_classification.enabledFor.contains("derep")) {
                        CLASSIFY_MAGS_DEREP(DEREPLICATE.out.bins_derep, FETCH_KRAKEN2_DB.out.kraken2_db, cache)
                        workflow_barrier = workflow_barrier.mix(CLASSIFY_MAGS_DEREP.out.taxonomy)
                    }

                    // annotate dereplicated MAGs
                    if (params.functional_annotation.enabledFor.contains("derep")) {
                        mags_derep_partitioned = PARTITION_DEREP_MAGS(DEREPLICATE.out.bins_derep, cache) | flatten
                        mags_derep_extracted = ANNOTATE_EGGNOG_MAGS_DEREP(mags_derep_partitioned, diamond_db, eggnog_db, cache)
                        workflow_barrier = workflow_barrier.mix(mags_derep_extracted)
                        if (params.abundance_estimation.enabledFor.contains("derep")) {
                            annotation_ft = MULTIPLY_TABLES(MAG_ABUNDANCE.out.feature_table, ANNOTATE_EGGNOG_MAGS_DEREP.out.extracted_annotations, "mags_derep", cache)
                            deepest_signal = annotation_ft.map { _type, key -> key }
                            workflow_barrier = workflow_barrier.mix(annotation_ft)
                            if (params.functional_annotation.annotation.extract.fetchArtifact) {
                                annotation_key = annotation_ft | map { _type, key -> key }
                                fetched_artifact = FETCH_MULTIPLIED_TABLE(annotation_key)
                                workflow_barrier = workflow_barrier.mix(fetched_artifact)
                            }
                        }
                    }
                }
            }
        }
    }

    qzv_reports_all = qzv_reports.unique().collect(flat: false).filter { it && it[1].size() > 0 }
    MAKE_REPORT(qzv_reports_all)

    // Fix sample cache permissions
    // We use workflow_barrier to wait for EVERYTHING
    final_signal = workflow_barrier.collect().map { true }

    // Collect all valid read IDs into a single list to prevent eager streaming
    sample_ids_list = reads_partitioned
        .map { id, _reads -> tuple(id, "${params.q2TemporaryCachesDir}/${id}") }
        .collect(flat: false)
    
    // Combine the collected list with the final signal, then unpack it back into a queue
    sample_ids_for_fix = sample_ids_list
        .combine(final_signal)
        .flatMap { rec ->
            def signal = rec[-1]       // last item
            def items  = rec[0..-2]    // all sample tuples
            items.collect { item -> tuple(item[0], item[1], signal) }
        }

    // logic:
    // 1. Always fix permissions when done
    // 2. Archive acts on the result (if enabled)
    fixed_sample_caches = FIX_CACHE_PERMISSIONS(sample_ids_for_fix)

    // Archive per-sample caches to reduce inode usage on Lustre
    if (params.archive) {
        ARCHIVE_SAMPLE_CACHE(fixed_sample_caches, true)
    }

    // Fix main cache permissions at the very end
    // We use the result of sample cache fixing (or deeper signal) to trigger this
    // Wait for fixed_sample_caches before fixing the main cache
    main_cache_input = Channel.of(tuple("main", "${params.q2cacheDir}"))
        .combine(fixed_sample_caches.collect().map { true })
        .map { rec -> tuple(rec[0], rec[1], rec[2]) }
        
    FIX_CACHE_PERMISSIONS_MAIN(main_cache_input)
}

// Add final summary section
workflow.onComplete {
    writeLog("\n==========================================")
    writeLog("WORKFLOW SUMMARY")
    writeLog("==========================================")
    writeLog("Completed at: " + new Date().format('yyyy-MM-dd HH:mm:ss'))
    writeLog("Duration    : ${workflow.duration}")
    writeLog("Success     : ${workflow.success}")
    writeLog("Exit status : ${workflow.exitStatus}")
    writeLog("Error report: ${workflow.errorReport ?: 'None'}")
    writeLog("Working dir : ${workflow.workDir}")
    writeLog("==========================================")
    
    // Write JSON report
    def jsonMap = [
        "id": "moshpit_sample_counts",
        "plot_type": "barplot",
        "pconfig": [
            "id": "sample_counts_plot",
            "title": "Samples Retained",
            "ylab": "# Samples"
        ],
        "data": executionStats.collectEntries { key, value -> [key, ["count": value]] }
    ]
    
    def jsonFile = new File(params.sampleReport)
    jsonFile.text = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(jsonMap))
    writeLog("Report written to: ${params.sampleReport}")
}
