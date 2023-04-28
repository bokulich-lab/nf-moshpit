#!/usr/bin/env nextflow

include { FETCH_SEQS } from '../modules/data_prep'
include { FETCH_GENOMES } from '../modules/data_prep'
include { SIMULATE_READS } from '../modules/data_prep'
include { SUBSAMPLE_READS } from '../modules/data_prep'
include { ASSEMBLE } from '../subworkflows/assembly'
include { BIN } from '../subworkflows/binning'
include { CLASSIFY_READS } from '../subworkflows/classification'
include { CLASSIFY_BINS } from '../subworkflows/classification'

nextflow.enable.dsl = 2

workflow MOSHPIT {

    // prepare input reads
    if (params.fondue.filesAccessionIds) {
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

    if (params.read_subsampling.enabled) {
        reads = SUBSAMPLE_READS(reads)
    }

    // assemble and evaluate contigs
    contigs = ASSEMBLE(reads)

    // bin contigs into MAGs and evaluate
    bins = BIN(contigs, reads)

    // classify reads and MAGs
    CLASSIFY_READS(reads)
    CLASSIFY_BINS(bins)
}
