include { INDEX_CONTIGS } from '../modules/genome_assembly'
include { MAP_READS_TO_CONTIGS } from '../modules/genome_assembly'
include { BIN_CONTIGS_METABAT } from '../modules/contig_binning'
include { EVALUATE_BINS_CHECKM } from '../modules/contig_binning'
include { EVALUATE_BINS_BUSCO } from '../modules/contig_binning'
include { FETCH_BUSCO_DB } from '../modules/contig_binning'

workflow BIN {
    take:
        contigs
        reads
        q2_cache
    main:
        indexed_contigs = INDEX_CONTIGS(contigs, q2_cache)
        mapped_reads = MAP_READS_TO_CONTIGS(indexed_contigs, reads, q2_cache)
        bins = BIN_CONTIGS_METABAT(contigs, mapped_reads, q2_cache)
        if (params.binning_qc.checkm.enabled) {
            EVALUATE_BINS_CHECKM(bins.bins, q2_cache)
        }
        busco_db = FETCH_BUSCO_DB(q2_cache)
        EVALUATE_BINS_BUSCO(bins.bins, busco_db, q2_cache)
    emit:
        bins = BIN_CONTIGS_METABAT.out.bins
        contig_map = BIN_CONTIGS_METABAT.out.contig_map
        unbinned_contigs = BIN_CONTIGS_METABAT.out.unbinned_contigs
        busco_results = EVALUATE_BINS_BUSCO.out.busco_results
}
