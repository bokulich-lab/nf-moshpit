#!/usr/bin/env nextflow

include {
    assembleMetaspades; assembleMegahit;
    evaluateContigs; indexContigs; mapReadsToContigs;
    binContigs; evaluateBins; classifyBins; classifyReads;
    drawTaxaBarplot; fetchSeqs
} from '../components'

nextflow.enable.dsl = 2

ids = Channel.fromPath(params.filesAccessionIds)

workflow TaxonomicClassificationBins {
    take:
        bins
    main:
        classification = classifyBins(bins)
        drawTaxaBarplot(classification.table, classification.taxonomy)
}

workflow TaxonomicClassificationReads {
    take:
        seqs
    main:
        classification = classifyReads(seqs)
        drawTaxaBarplot(classification.table, classification.taxonomy)
}

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
    emit:
        bins
}

workflow MetaSPAdes {
    main:
        reads = fetchSeqs(ids)
        contigs = assembleMetaspades(reads.paired)
        bins = ContigQCAndBinnig(contigs, reads.paired)
//         TaxonomicClassificationBins(bins)
//         TaxonomicClassificationReads(simulated_reads.reads)
}

workflow MEGAHIT {
    main:
        reads = fetchSeqs(ids)
        contigs = assembleMegahit(reads.paired)
        bins = ContigQCAndBinnig(contigs, reads.paired)
//         TaxonomicClassificationBins(bins)
//         TaxonomicClassificationReads(simulated_reads.reads)
}
