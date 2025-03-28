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
include { SUBSAMPLE_READS } from './modules/data_prep'
include { REMOVE_HOST } from './modules/data_prep'
include { PROCESS_READS_FASTP } from './modules/data_prep'
include { VISUALIZE_FASTP } from './modules/data_prep'
include { PARTITION_DEREP_MAGS } from './modules/data_prep'
include { COLLATE_PARTITIONS } from './modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_FASTP_REPORTS } from './modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_READS } from './modules/data_prep'
include { TABULATE_READ_COUNTS } from './modules/data_prep'
include { FILTER_SAMPLES } from './modules/data_prep'
include { FILTER_SAMPLES as PARTITION_READS } from './modules/data_prep'
include { ASSEMBLE } from './subworkflows/assembly'
include { BIN } from './subworkflows/binning'
include { BIN_NO_BUSCO } from './subworkflows/binning'
include { DEREPLICATE } from './subworkflows/dereplication'
include { CLASSIFY_READS } from './subworkflows/classification'
include { CLASSIFY_CONTIGS } from './subworkflows/classification'
include { CLASSIFY_MAGS } from './subworkflows/classification'
include { CLASSIFY_MAGS_DEREP } from './subworkflows/classification'
include { ANNOTATE_EGGNOG_MAGS_DEREP } from './subworkflows/functional_annotation'
include { ANNOTATE_EGGNOG_MAGS } from './subworkflows/functional_annotation'
include { ANNOTATE_EGGNOG_CONTIGS } from './subworkflows/functional_annotation'
include { ESTIMATE_ABUNDANCE } from './subworkflows/abundance_estimation'
include { FETCH_DIAMOND_DB } from './modules/functional_annotation'
include { FETCH_EGGNOG_DB } from './modules/functional_annotation'
include { FETCH_KRAKEN2_DB } from './modules/taxonomic_classification'
include { MULTIPLY_TABLES } from './modules/functional_annotation'

nextflow.enable.dsl = 2

workflow {
    cache = INIT_CACHE()

    def logFile = new File( "${params.sampleReport}" )
    def writeLog = { value ->
        logFile << value + "\n"
    }

    // Log header with workflow version and timestamp
    writeLog("======== MOSHPIT WORKFLOW REPORT =========")
    writeLog("Run ID: ${params.runId}")
    writeLog("Start time: " + new Date().format('yyyy-MM-dd HH:mm:ss'))
    writeLog("==========================================")
    writeLog("\n=== CONFIGURATION ===")
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
        reads | count | subscribe { writeLog("Samples imported from manifest: " + it) }
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
        reads | count | subscribe { writeLog("Samples partitioned from an input artifact: " + it) }
    } else if (params.fondueAccessionIds) {
        ids = Channel
            .fromPath(params.fondueAccessionIds)
            .splitCsv(header: true, sep: '\t')
            .map { row -> row.ID }
        
        writeLog("Reading SRA accessions from: ${params.fondueAccessionIds}")
        writeLog("SRA accessions to fetch: " + ids.count().val)
        
        fetched_reads = FETCH_SEQS(ids)
        reads = (params.fondue.paired) ? fetched_reads.paired : fetched_reads.single
        reads | count | subscribe { writeLog("Samples returned from fondue: " + it) }
    } else if (params.read_simulation.sampleGenomes) {
        genomes = Channel.fromPath(params.read_simulation.sampleGenomes)
        ids = Channel.of(params.read_simulation.sampleNames.split(','))
        
        writeLog("Simulating reads from provided genomes: ${params.read_simulation.sampleGenomes}")
        writeLog("Number of samples to simulate: ${params.read_simulation.sampleNames.split(',').size()}")
        writeLog("Reads per sample: ${params.read_simulation.readCount}")
        
        ids_with_genomes = ids.combine(genomes)
        simulated_reads = SIMULATE_READS(ids_with_genomes)
        reads = simulated_reads.reads
        reads | count | subscribe { writeLog("Samples simulated: " + it) }
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
        reads | count | subscribe { writeLog("Samples simulated: " + it) }
    }

    reads_partitioned = reads

    // subsample reads
    if (params.read_subsampling.enabled) {
        reads_partitioned = SUBSAMPLE_READS(reads_partitioned)
        reads_partitioned | count | subscribe { writeLog("Samples after subsampling: " + it) }
    }

    // perform read QC and trimming
    fastp_results = PROCESS_READS_FASTP(reads_partitioned)
    reads_partitioned = fastp_results | map { _id, reads, report -> [_id, reads] }
    reads_partitioned | count | subscribe { writeLog("Samples after fastp processing: " + it) }
    fastp_reports = fastp_results | map { _id, reads, report -> tuple(_id, report) } | collect(flat: false)
    fastp_reports_all = COLLATE_FASTP_REPORTS(fastp_reports, "${params.runId}_fastp_reports", "fastp collate-fastp-reports", "--i-reports", "--o-collated-reports", true)
    VISUALIZE_FASTP(fastp_reports_all, cache)

    // remove host reads
    if (params.host_removal.enabled) {
        filtering_results = REMOVE_HOST(reads_partitioned)
        reads_partitioned = filtering_results.reads
        reads_partitioned | count | subscribe { writeLog("Samples after host removal: " + it) }
    }

    if (params.taxonomic_classification.enabledFor != "") {
        FETCH_KRAKEN2_DB()
    }

    // remove samples with low read counts
    if (params.sample_filtering.enabled) {
        read_counts = TABULATE_READ_COUNTS(reads_partitioned)
        reads_with_counts = reads_partitioned.combine(read_counts, by: 0)
        reads_partitioned = FILTER_SAMPLES(reads_with_counts, "'\"Demultiplexed sequence count\">${params.sample_filtering.minReads}'", false)
        reads_partitioned | count | subscribe { writeLog("Samples after filtering by read count: " + it) }
    }


    // classify reads
    if (params.taxonomic_classification.enabledFor.contains("reads")) {
        CLASSIFY_READS(reads_partitioned, FETCH_KRAKEN2_DB.out.kraken2_db, FETCH_KRAKEN2_DB.out.bracken_db, cache)
    }

    // assemble and evaluate
    if (params.genome_assembly.enabled) {
        contigs = ASSEMBLE(reads_partitioned, cache)

        contigs.contigs | count | subscribe { writeLog("Samples after contig assembly and filtering: " + it) }

        if (params.functional_annotation.enabledFor != "") {
            diamond_db = FETCH_DIAMOND_DB()
            eggnog_db = FETCH_EGGNOG_DB()
        }

        // classify contigs
        if (params.taxonomic_classification.enabledFor.contains("contigs")) {
            CLASSIFY_CONTIGS(contigs.contigs, FETCH_KRAKEN2_DB.out.kraken2_db, cache)
        }

        // annotate contigs
        if (params.functional_annotation.enabledFor.contains("contigs")) {
            ANNOTATE_EGGNOG_CONTIGS(contigs.contigs, diamond_db, eggnog_db)
        }

        // bin contigs into MAGs and evaluate
        if (params.binning.enabled) {
            if (params.binning.qc.busco.enabled) {
                binning_results = BIN(contigs.contigs, contigs.mapped_reads, cache)
            } else {
                binning_results = BIN_NO_BUSCO(contigs.contigs, contigs.mapped_reads, cache)
            }
            
            binning_results.bins | count | subscribe { writeLog("Samples after binning: " + it) }
            
            // classify MAGs
            if (params.taxonomic_classification.enabledFor.contains("mags")) {
                CLASSIFY_MAGS(binning_results.bins, FETCH_KRAKEN2_DB.out.kraken2_db, cache)
            }

            // annotate MAGs
            if (params.functional_annotation.enabledFor.contains("mags")) {
                ANNOTATE_EGGNOG_MAGS(binning_results.bins, diamond_db, eggnog_db)
            }


            if (params.dereplication.enabled) {
                DEREPLICATE(binning_results.bins_collated, cache)
                
                // estimate abundance
                if (params.mag_abundance.enabled) {
                    ESTIMATE_ABUNDANCE(DEREPLICATE.out.bins_derep, reads_partitioned, cache)
                }

                if (params.taxonomic_classification.enabledFor.contains("derep") || params.functional_annotation.enabledFor.contains("derep")) {
                    // classify dereplicated MAGs
                    if (params.taxonomic_classification.enabledFor.contains("derep")) {
                        CLASSIFY_MAGS_DEREP(DEREPLICATE.out.bins_derep, FETCH_KRAKEN2_DB.out.kraken2_db, cache)
                    }

                    // annotate dereplicated MAGs
                    if (params.functional_annotation.enabledFor.contains("derep")) {
                        mags_derep_partitioned = PARTITION_DEREP_MAGS(DEREPLICATE.out.bins_derep, cache) | flatten
                        ANNOTATE_EGGNOG_MAGS_DEREP(mags_derep_partitioned, diamond_db, eggnog_db, cache)
                        if (params.mag_abundance.enabled) {
                            annotation_ft = MULTIPLY_TABLES(ESTIMATE_ABUNDANCE.out.feature_table, ANNOTATE_EGGNOG_MAGS_DEREP.out.extracted_annotations, "mags_derep", cache)
                            if (params.functional_annotation.annotation.extract.fetchArtifact) {
                                annotation_key = annotation_ft | map { _type, key -> key }
                                FETCH_MULTIPLIED_TABLE(annotation_key)
                            }
                        }
                    }
                }
            }
        }
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
    }
}
