#!/usr/bin/env nextflow

include { PREPARE_DATA } from '../subworkflows/prep'
include { ASSEMBLE } from '../subworkflows/assembly'
include { BIN } from '../subworkflows/binning'
include { CLASSIFY_READS } from '../subworkflows/classification'
include { CLASSIFY_BINS } from '../subworkflows/classification'

nextflow.enable.dsl = 2

workflow MOSHPIT {

    // prepare input reads
    reads = PREPARE_DATA()

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
