include { INDEX_CONTIGS } from '../modules/genome_assembly'
include { MAP_READS_TO_CONTIGS } from '../modules/genome_assembly'
include { BIN_CONTIGS_METABAT } from '../modules/contig_binning'
include { EVALUATE_BINS } from '../modules/contig_binning'

workflow BIN {
    take:
        contigs
        reads
        q2_cache
    main:
        indexed_contigs = INDEX_CONTIGS(contigs, q2_cache)
        mapped_reads = MAP_READS_TO_CONTIGS(indexed_contigs, reads, q2_cache)
        bins = BIN_CONTIGS_METABAT(contigs, mapped_reads, q2_cache)
        if (params.binning_qc.enabled) {
            bins_qc = EVALUATE_BINS(bins.bins)
        }
    emit:
        bins = BIN_CONTIGS_METABAT.out.bins
        contig_map = BIN_CONTIGS_METABAT.out.contig_map
        unbinned_contigs = BIN_CONTIGS_METABAT.out.unbinned_contigs
}
