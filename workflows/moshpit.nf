#!/usr/bin/env nextflow

include { INIT_CACHE } from '../modules/data_prep'
include { FETCH_SEQS } from '../modules/data_prep'
include { FETCH_GENOMES } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_CONTIGS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS } from '../modules/data_prep'
include { FETCH_ARTIFACT as FETCH_ARTIFACT_BINS_DEREP } from '../modules/data_prep'
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
include { ANNOTATE_EGGNOG_MAGS } from '../subworkflows/functional_annotation'
include { ANNOTATE_EGGNOG_CONTIGS } from '../subworkflows/functional_annotation'

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
        genomes = FETCH_GENOMES()
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
        reads = REMOVE_HOST(reads, cache)
    }

    // classify reads
    if (params.taxonomic_classification.enabled) {
        CLASSIFY_READS(reads, cache)
    }

    // assemble and evaluate
    if (params.genome_assembly.enabled) {
        contigs = ASSEMBLE(reads, cache)
        FETCH_ARTIFACT_CONTIGS(contigs, "contigs.qza")


        // annotate contigs
        if (params.functional_annotation.enabled) {
            ANNOTATE_EGGNOG_CONTIGS(contigs, cache)
        }

        // bin contigs into MAGs and evaluate
        if (params.binning.enabled) {
            BIN(contigs, reads, cache)
            DEREPLICATE(BIN.out.bins, cache)
            FETCH_ARTIFACT_BINS(BIN.out.bins, "mags.qza")
            FETCH_ARTIFACT_BINS_DEREP(DEREPLICATE.out.bins_derep, "mags-derep.qza")

            // classify MAGs
            if (params.taxonomic_classification.enabled) {
                CLASSIFY_MAGS(DEREPLICATE.out.bins_derep, cache)
            }
        }

        // annotate MAGs
        if (params.functional_annotation.enabled) {
            ANNOTATE_EGGNOG_MAGS(DEREPLICATE.out.bins_derep, cache)
        }
    }
}
