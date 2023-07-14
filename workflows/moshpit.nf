#!/usr/bin/env nextflow

include { FETCH_SEQS } from '../modules/data_prep'
include { FETCH_GENOMES } from '../modules/data_prep'
include { SIMULATE_READS } from '../modules/data_prep'
include { SUBSAMPLE_READS } from '../modules/data_prep'
include { SUMMARIZE_READS; SUMMARIZE_READS as SUMMARIZE_TRIMMED } from '../modules/data_prep'
include { REMOVE_HOST } from '../modules/data_prep'
include { TRIM_READS } from '../modules/data_prep'
include { ASSEMBLE } from '../subworkflows/assembly'
include { BIN } from '../subworkflows/binning'
include { CLASSIFY_READS } from '../subworkflows/classification'
include { CLASSIFY_BINS } from '../subworkflows/classification'

nextflow.enable.dsl = 2

workflow MOSHPIT {

    // prepare input reads
    if (params.inputReads) {
        reads = params.inputReads
    } else if (params.fondue.filesAccessionIds) {
        ids = Channel.fromPath(params.fondue.filesAccessionIds)
        fetched_reads = FETCH_SEQS(ids)
        reads = (params.fondue.paired) ? fetched_reads.paired : fetched_reads.single
    } else if (params.read_simulation.sampleGenomes) {
        genomes = Channel.fromPath(params.read_simulation.sampleGenomes)
        simulated_reads = SIMULATE_READS(genomes)
        reads = simulated_reads.reads
    } else {
        genomes = FETCH_GENOMES()
        simulated_reads = SIMULATE_READS(genomes)
        reads = simulated_reads.reads
    }

    // subsample reads
    if (params.read_subsampling.enabled) {
        reads = SUBSAMPLE_READS(reads)
    }

    // perform read QC
    SUMMARIZE_READS(reads, "raw")

    // trim reads
    if (params.read_trimming.enabled) {
        reads = TRIM_READS(reads)
        // repeat read QC
        SUMMARIZE_TRIMMED(reads, "trimmed")
    }

    // remove host reads
    if (params.host_removal.enabled) {
        reads = REMOVE_HOST(reads)
    }

    // classify reads
    if (params.taxonomic_classification.enabled) {
        CLASSIFY_READS(reads)
    }

    // assemble and evaluate
    if (params.genome_assembly.enabled) {
        contigs = ASSEMBLE(reads)
        // bin contigs into MAGs and evaluate
        if (params.binning.enabled) {
            bins = BIN(contigs, reads)
            // classify MAGs
            if (params.taxonomic_classification.enabled) {
                CLASSIFY_BINS(bins)
            }
        }
    }
}
