#!/usr/bin/env nextflow

include { INIT_CACHE } from './modules/data_prep'
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
include { PARTITION_ARTIFACT as PARTITION_READS } from './modules/data_prep'
include { PARTITION_ARTIFACT as PARTITION_MAGS } from './modules/data_prep'
include { COLLATE_PARTITIONS } from './modules/data_prep'
include { COLLATE_PARTITIONS as COLLATE_FASTP_REPORTS } from './modules/data_prep'
include { TABULATE_READ_COUNTS } from './modules/data_prep'
include { FILTER_SAMPLES } from './modules/data_prep'
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

    // prepare input reads
    if (params.inputReads) {
        reads = Channel.fromPath(params.inputReads)
    } else if (params.fondue.filesAccessionIds) {
        ids = Channel.fromPath(params.fondue.filesAccessionIds)
        fetched_reads = FETCH_SEQS(ids, cache)
        reads = (params.fondue.paired) ? fetched_reads.paired : fetched_reads.single
    } else if (params.read_simulation.sampleGenomes) {
        genomes = Channel.fromPath(params.read_simulation.sampleGenomes)
        simulated_reads = SIMULATE_READS(genomes, cache)
        reads = simulated_reads.reads
    } else {
        genomes = FETCH_GENOMES(cache)
        simulated_reads = SIMULATE_READS(genomes, cache)
        reads = simulated_reads.reads
    }

    // split reads into partitions
    reads_prefix = "${params.runId}_reads_partitioned_"
    reads_partitioned = PARTITION_READS(reads, reads_prefix, "demux partition-samples-paired", "--i-demux", "--o-partitioned-demux", true) | flatten
    reads_partitioned = reads_partitioned.map { partition ->
        def path = java.nio.file.Paths.get(partition.toString())
        def filename = path.getFileName().toString()
        tuple(filename.substring(reads_prefix.length()), partition)
    }

    // subsample reads
    if (params.read_subsampling.enabled) {
        reads_partitioned = SUBSAMPLE_READS(reads_partitioned, cache)
    }

    // perform read QC and trimming
    fastp_results = PROCESS_READS_FASTP(reads_partitioned, cache)
    reads_partitioned = fastp_results | map { _id, reads, report -> [_id, reads] }
    fastp_reports = fastp_results | map { _id, reads, report -> report } | collect
    fastp_reports_all = COLLATE_FASTP_REPORTS(fastp_reports, "${params.runId}_fastp_reports", "fastp collate-fastp-reports", "--i-reports", "--o-collated-reports", true)
    VISUALIZE_FASTP(fastp_reports_all, cache)

    // remove host reads
    if (params.host_removal.enabled) {
        filtering_results = REMOVE_HOST(reads_partitioned, cache)
        reads_partitioned = filtering_results.reads
    }

    if (params.taxonomic_classification.enabledFor != "") {
        FETCH_KRAKEN2_DB(cache)
    }

    // remove samples with low read counts
    if (params.sample_filtering.enabled) {
        read_counts = TABULATE_READ_COUNTS(reads_partitioned, cache)
        reads_with_counts = reads_partitioned.combine(read_counts, by: 0)
        reads_partitioned = FILTER_SAMPLES(reads_with_counts, "'\"Demultiplexed sequence count\">${params.sample_filtering.min_reads}'", cache)
    }


    // classify reads
    if (params.taxonomic_classification.enabledFor.contains("reads")) {
        CLASSIFY_READS(reads_partitioned, FETCH_KRAKEN2_DB.out.kraken2_db, FETCH_KRAKEN2_DB.out.bracken_db, cache)
    }

    // assemble and evaluate
    if (params.genome_assembly.enabled) {
        contigs = ASSEMBLE(reads_partitioned, cache)

        if (params.functional_annotation.enabledFor != "") {
            diamond_db = FETCH_DIAMOND_DB(cache)
            eggnog_db = FETCH_EGGNOG_DB(cache)
        }

        // classify contigs
        if (params.taxonomic_classification.enabledFor.contains("contigs")) {
            CLASSIFY_CONTIGS(contigs.contigs, FETCH_KRAKEN2_DB.out.kraken2_db, cache)
        }

        // annotate contigs
        if (params.functional_annotation.enabledFor.contains("contigs")) {
            ANNOTATE_EGGNOG_CONTIGS(contigs.contigs, diamond_db, eggnog_db, cache)
        }

        // bin contigs into MAGs and evaluate
        if (params.binning.enabled) {
            if (params.binning.qc.busco.enabled) {
                binning_results = BIN(contigs.contigs, contigs.mapped_reads, cache)
            } else {
                binning_results = BIN_NO_BUSCO(contigs.contigs, contigs.mapped_reads, cache)
            }
            
            // classify MAGs
            if (params.taxonomic_classification.enabledFor.contains("mags")) {
                CLASSIFY_MAGS(binning_results.bins, FETCH_KRAKEN2_DB.out.kraken2_db, cache)
            }

            // annotate MAGs
            if (params.functional_annotation.enabledFor.contains("mags")) {
                ANNOTATE_EGGNOG_MAGS(binning_results.bins, diamond_db, eggnog_db, cache)
            }


            if (params.dereplication.enabled) {
                DEREPLICATE(binning_results.bins | map { _id, _key -> _key } | collect, cache)
                
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
                        mags_derep_partitioned = PARTITION_MAGS(DEREPLICATE.out.bins_derep, "${params.runId}_mags_derep_partitioned_", "types partition-feature-data-mags", "--i-mags", "--o-partitioned-mags", false) | flatten
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
}
