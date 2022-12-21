include { INDEX_CONTIGS } from '../modules/genome_assembly'
include { MAP_READS_TO_CONTIGS } from '../modules/genome_assembly'
include { BIN_CONTIGS_METABAT } from '../modules/contig_binning'
include { EVALUATE_BINS } from '../modules/contig_binning'

workflow BIN {
    take:
        contigs
        reads
    main:
        indexed_contigs = INDEX_CONTIGS(contigs)
        mapped_reads = MAP_READS_TO_CONTIGS(indexed_contigs, reads)
        bins = BIN_CONTIGS_METABAT(contigs, mapped_reads)
        bins_qc = EVALUATE_BINS(bins)
    emit:
        bins
}
