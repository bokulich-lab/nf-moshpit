#!/usr/bin/env nextflow

include {
    simulateReads; assembleMetaspades; assembleMegahit;
    evaluateContigs; indexContigs; mapReadsToContigs;
    binContigs; evaluateBins
} from '../components'

nextflow.enable.dsl = 2

genomes = Channel.fromPath(params.genomes)

workflow ContigQCAndBinnig {
    take:
        contigs
        reads
    main:
        contig_qc = evaluateContigs(contigs, reads)
        indexed_contigs = indexContigs(contigs)
        mapped_reads = mapReadsToContigs(indexed_contigs, reads)
        bins = binContigs(contigs, mapped_reads)
        bins_qc = evaluateBins(bins)
}

workflow MetaSPAdes {
    main:
        simulated_reads = simulateReads(genomes)
        contigs = assembleMetaspades(simulated_reads.reads)
        ContigQCAndBinnig(contigs, simulated_reads.reads)
}

workflow MEGAHIT {
    main:
        simulated_reads = simulateReads(genomes)
        contigs = assembleMegahit(simulated_reads.reads)
        ContigQCAndBinnig(contigs, simulated_reads.reads)
}
