#!/usr/bin/env nextflow

include { FETCH_SEQS } from '../modules/data_prep'
include { FETCH_GENOMES } from '../modules/data_prep'
include { SIMULATE_READS } from '../modules/data_prep'
include { ASSEMBLE } from '../subworkflows/assembly'
include { BIN } from '../subworkflows/binning'
include { CLASSIFY_READS } from '../subworkflows/classification'
include { CLASSIFY_BINS } from '../subworkflows/classification'

nextflow.enable.dsl = 2

workflow MOSHPIT {

    // prepare input reads
    if (params.filesAccessionIds) {
        ids = Channel.fromPath(params.filesAccessionIds)
        fetched_reads = FETCH_SEQS(ids)
        reads = (params.paired) ? fetched_reads.paired : fetched_reads.single
    } else if (params.sampleGenomes) {
        genomes = Channel.fromPath(params.sampleGenomes)
        simulated_reads = SIMULATE_READS(genomes)
        reads = simulated_reads.reads
    } else {
        genomes = FETCH_GENOMES()
        simulated_reads = SIMULATE_READS(genomes)
        reads = simulated_reads.reads
    }

    // assemble and evaluate contigs
    contigs = ASSEMBLE(reads)

    // bin contigs into MAGs and evaluate
    bins = BIN(contigs, reads)

    // classify reads and MAGs
    CLASSIFY_READS(reads)
    CLASSIFY_BINS(bins)
}
