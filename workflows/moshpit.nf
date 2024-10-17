#!/usr/bin/env nextflow

include { INIT_CACHE } from '../modules/data_prep'
include { FETCH_SEQS } from '../modules/data_prep'
include { FETCH_GENOMES } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_CONTIGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS_DEREP } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS_DEREP_FT } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS_FILTERED } from '../modules/data_prep'
include { SIMULATE_READS } from '../modules/data_prep'
include { SUBSAMPLE_READS } from '../modules/data_prep'
include { SUMMARIZE_READS; SUMMARIZE_READS as SUMMARIZE_TRIMMED } from '../modules/data_prep'
include { REMOVE_HOST } from '../modules/data_prep'
include { TRIM_READS } from '../modules/data_prep'
include { ASSEMBLE } from '../subworkflows/assembly'
include { BIN } from '../subworkflows/binning'
include { DEREPLICATE } from '../subworkflows/dereplication'
include { CLASSIFY_READS } from '../subworkflows/classification'
include { CLASSIFY_MAGS } from '../subworkflows/classification'
include { ANNOTATE_EGGNOG_MAGS_DEREP } from '../subworkflows/functional_annotation'
include { ANNOTATE_EGGNOG_CONTIGS } from '../subworkflows/functional_annotation'
include { ESTIMATE_ABUNDANCE } from '../subworkflows/abundance_estimation'
include { FETCH_DIAMOND_DB } from '../modules/functional_annotation'
include { FETCH_EGGNOG_DB } from '../modules/functional_annotation'
include { FETCH_KRAKEN2_DB } from '../modules/taxonomic_classification'
nextflow.enable.dsl = 2

workflow MOSHPIT {
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

    // subsample reads
    if (params.read_subsampling.enabled) {
        reads = SUBSAMPLE_READS(reads, cache)
    }

    // perform read QC
    SUMMARIZE_READS(reads, "raw", cache)

    // trim reads
    if (params.read_trimming.enabled) {
        reads = TRIM_READS(reads, cache)

        // repeat read QC
        SUMMARIZE_TRIMMED(reads, "trimmed", cache)
    }

    // remove host reads
    if (params.host_removal.enabled) {
        filtering_results = REMOVE_HOST(reads, cache)
        reads = filtering_results.reads
    }

    // classify reads
    if (params.taxonomic_classification.enabled) {
        FETCH_KRAKEN2_DB(cache)
        CLASSIFY_READS(reads, FETCH_KRAKEN2_DB.out.kraken2_db, FETCH_KRAKEN2_DB.out.bracken_db, cache)
    }

    // assemble and evaluate
    if (params.genome_assembly.enabled) {
        contigs = ASSEMBLE(reads, cache)
        FETCH_ARTIFACT_CONTIGS(contigs, "contigs.qza")

        // fetch EggNOG databases
        diamond_db = FETCH_DIAMOND_DB(cache)
        eggnog_db = FETCH_EGGNOG_DB(cache)

        // annotate contigs
        if (params.functional_annotation.enabled) {
            ANNOTATE_EGGNOG_CONTIGS(contigs, diamond_db, eggnog_db, cache)
        }

        // bin contigs into MAGs and evaluate
        if (params.binning.enabled) {
            BIN(contigs, reads, cache)

            if (params.dereplication.enabled) {
                DEREPLICATE(BIN.out.bins, BIN.out.busco_results, cache)
                FETCH_ARTIFACT_BINS(BIN.out.bins, "mags.qza")
                FETCH_ARTIFACT_BINS_DEREP(DEREPLICATE.out.bins_derep, "mags-derep.qza")
                if (params.dereplication.filtering.enabled) {
                    FETCH_ARTIFACT_BINS_FILTERED(DEREPLICATE.out.bins_filtered, "mags-filtered.qza")
                }

                // estimate abundance
                if (params.mag_abundance.enabled) {
                    ESTIMATE_ABUNDANCE(DEREPLICATE.out.bins_derep, reads, cache)
                    FETCH_ARTIFACT_BINS_DEREP_FT(ESTIMATE_ABUNDANCE.out.feature_table, "mags-derep-ft.qza")
                }

                // classify dereplicated MAGs
                if (params.taxonomic_classification.enabled) {
                    CLASSIFY_MAGS(DEREPLICATE.out.bins_derep, FETCH_KRAKEN2_DB.out.bracken_db, cache)
                }

                // annotate dereplicated MAGs
                if (params.functional_annotation.enabled) {
                    ANNOTATE_EGGNOG_MAGS_DEREP(DEREPLICATE.out.bins_derep, diamond_db, eggnog_db, cache)
                }
            }
        }
    }
}
